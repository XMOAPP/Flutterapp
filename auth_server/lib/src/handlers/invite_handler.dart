part of xmo_auth_server;

final _inviteMemoryStore = <String, _InviteRecord>{};
Future<void> _inviteStoreTail = Future<void>.value();

Future<void> _createInviteLink(HttpRequest request) async {
  _inviteDisableCaching(request);
  if (!_inviteConfig.isConfigured) {
    await _inviteUnavailable(request);
    return;
  }
  final session = await _inviteSession(request);
  if (session == null) return;
  final body = await _readJson(request);
  final roomId = _inviteRoomId(body['roomId']);
  if (roomId == null) {
    throw const _BadRequestException('Valid roomId is required');
  }

  final room = await _inviteLoadRoom(roomId, session.token);
  if (!_inviteCanManage(room, session.userId)) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Only a room administrator can manage invite links',
    });
    return;
  }
  final joinMode = _inviteJoinMode(room);
  if (joinMode == null) {
    await _json(request, HttpStatus.conflict, {
      'success': false,
      'error': room.encrypted
          ? 'Enable request to join before creating a private invite link'
          : 'This room must allow public joining before creating a link',
    });
    return;
  }

  final now = DateTime.now().toUtc();
  final expiryDays =
      _inviteBoundedInt(body['expiryDays'], min: 1, max: 30) ?? 30;
  final maxUses = _inviteBoundedInt(body['maxUses'], min: 1, max: 100000);
  final token = _inviteRandomToken();
  final tokenHash = _inviteTokenHash(token);
  final linkId = _inviteRandomId(12);
  final encryptedToken = await _inviteEncryptToken(token);
  final record = _InviteRecord(
    tokenHash: tokenHash,
    encryptedToken: encryptedToken,
    linkId: linkId,
    roomId: roomId,
    roomName: room.name,
    roomType: room.roomType,
    avatarUrl: room.avatarUrl,
    topic: room.topic,
    memberCount: room.memberCount,
    joinMode: joinMode,
    createdBy: session.userId,
    createdAt: now,
    expiresAt: now.add(Duration(days: expiryDays)),
    maxUses: maxUses,
    usedCount: 0,
    active: true,
    redeemedUserIds: <String>{},
  );
  await _withInviteStore((records) {
    for (final existing in records.values) {
      if (existing.roomId == roomId && existing.active) {
        existing.active = false;
      }
    }
    records[tokenHash] = record;
  });
  await _json(request, HttpStatus.ok, {
    'success': true,
    'invite': record.toOwnerJson(token, _inviteConfig.webBaseUrl),
  });
}

Future<void> _listInviteLinks(HttpRequest request) async {
  _inviteDisableCaching(request);
  if (!_inviteConfig.isConfigured) {
    await _inviteUnavailable(request);
    return;
  }
  final session = await _inviteSession(request);
  if (session == null) return;
  final body = await _readJson(request);
  final roomId = _inviteRoomId(body['roomId']);
  if (roomId == null)
    throw const _BadRequestException('Valid roomId is required');
  final room = await _inviteLoadRoom(roomId, session.token);
  if (!_inviteCanManage(room, session.userId)) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Only a room administrator can manage invite links',
    });
    return;
  }
  final records = await _withInviteStore((latest) {
    for (final record in latest.values) {
      if (record.roomId == roomId) {
        record.refreshRoomSnapshot(room);
      }
    }
    return Map<String, _InviteRecord>.of(latest);
  });
  final result = <Map<String, dynamic>>[];
  for (final record
      in records.values.where((entry) => entry.roomId == roomId)) {
    final token = await _inviteDecryptToken(record.encryptedToken);
    if (token != null) {
      result.add(record.toOwnerJson(token, _inviteConfig.webBaseUrl));
    }
  }
  result.sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
  await _json(request, HttpStatus.ok, {'success': true, 'invites': result});
}

Future<void> _revokeInviteLink(HttpRequest request) async {
  _inviteDisableCaching(request);
  if (!_inviteConfig.isConfigured) {
    await _inviteUnavailable(request);
    return;
  }
  final session = await _inviteSession(request);
  if (session == null) return;
  final body = await _readJson(request);
  final linkId = body['linkId']?.toString().trim() ?? '';
  if (linkId.isEmpty) throw const _BadRequestException('linkId is required');
  final records = await _readInviteRecords();
  _InviteRecord? target;
  for (final record in records.values) {
    if (record.linkId == linkId) {
      target = record;
      break;
    }
  }
  if (target == null) {
    await _json(request, HttpStatus.notFound,
        {'success': false, 'error': 'Invite not found'});
    return;
  }
  final room = await _inviteLoadRoom(target.roomId, session.token);
  if (!_inviteCanManage(room, session.userId)) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Only a room administrator can manage invite links',
    });
    return;
  }
  await _withInviteStore((latest) {
    for (final record in latest.values) {
      if (record.linkId == linkId) record.active = false;
    }
  });
  await _json(request, HttpStatus.ok, {'success': true});
}

Future<void> _previewInviteLink(HttpRequest request) async {
  _inviteDisableCaching(request);
  if (!_inviteConfig.isConfigured) {
    await _inviteUnavailable(request);
    return;
  }
  final token = InviteEndpointModule.tokenFromPreviewPath(request.uri.path);
  final record = await _inviteRecordForToken(token);
  if (record == null || !record.canBeUsed) {
    await _json(request, HttpStatus.notFound, {
      'success': false,
      'error': 'This invite link is invalid, expired, or revoked',
    });
    return;
  }
  await _json(request, HttpStatus.ok, {
    'success': true,
    'invite': record.toPublicJson(),
  });
}

Future<void> _serveInviteAvatar(HttpRequest request) async {
  _inviteDisableCaching(request);
  final token = InviteEndpointModule.tokenFromAvatarPath(request.uri.path);
  final record = await _inviteRecordForToken(token);
  if (!_inviteConfig.canProxyAvatars ||
      record == null ||
      !record.canBeUsed ||
      record.avatarUrl == null) {
    await _inviteAvatarNotFound(request);
    return;
  }

  final mxc = Uri.tryParse(record.avatarUrl!);
  if (mxc == null ||
      mxc.scheme != 'mxc' ||
      mxc.authority != _inviteConfig.serverName ||
      mxc.pathSegments.length != 1 ||
      mxc.pathSegments.single.isEmpty) {
    await _inviteAvatarNotFound(request);
    return;
  }

  final mediaUri = Uri.parse(_inviteConfig.homeserverUrl).replace(
    pathSegments: [
      '_matrix',
      'client',
      'v1',
      'media',
      'thumbnail',
      mxc.authority,
      mxc.pathSegments.single,
    ],
    queryParameters: const {
      'width': '192',
      'height': '192',
      'method': 'crop',
      'allow_remote': 'false',
    },
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final upstream = await client.getUrl(mediaUri);
    upstream.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${_inviteConfig.mediaAccessToken}',
    );
    final response =
        await upstream.close().timeout(const Duration(seconds: 12));
    final contentType =
        response.headers.value(HttpHeaders.contentTypeHeader)?.split(';').first;
    const allowedTypes = {
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/avif',
    };
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !allowedTypes.contains(contentType)) {
      await response.drain<void>();
      await _inviteAvatarNotFound(request);
      return;
    }

    const maxAvatarBytes = 2 * 1024 * 1024;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxAvatarBytes) {
        await _inviteAvatarNotFound(request);
        return;
      }
      bytes.add(chunk);
    }
    final payload = bytes.takeBytes();
    if (payload.isEmpty) {
      await _inviteAvatarNotFound(request);
      return;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.contentTypeHeader, contentType!)
      ..headers.set(HttpHeaders.contentLengthHeader, payload.length)
      ..add(payload);
    await request.response.close();
  } on TimeoutException {
    await _inviteAvatarNotFound(request);
  } on SocketException {
    await _inviteAvatarNotFound(request);
  } finally {
    client.close(force: true);
  }
}

Future<void> _inviteAvatarNotFound(HttpRequest request) => _json(
      request,
      HttpStatus.notFound,
      {'success': false, 'error': 'Invite avatar unavailable'},
    );

Future<void> _redeemInviteLink(HttpRequest request) async {
  _inviteDisableCaching(request);
  if (!_inviteConfig.isConfigured) {
    await _inviteUnavailable(request);
    return;
  }
  final session = await _inviteSession(request);
  if (session == null) return;
  final token = InviteEndpointModule.tokenFromRedeemPath(request.uri.path);
  final tokenHash = token == null ? '' : _inviteTokenHash(token);
  final records = await _readInviteRecords();
  final record = records[tokenHash];
  if (record == null || !record.canBeUsedBy(session.userId)) {
    await _json(request, HttpStatus.notFound, {
      'success': false,
      'error': 'This invite link is invalid, expired, or revoked',
    });
    return;
  }
  final redeemed = await _withInviteStore((latest) {
    final current = latest[tokenHash];
    if (current == null || !current.canBeUsedBy(session.userId)) return false;
    if (current.redeemedUserIds.add(session.userId)) current.usedCount += 1;
    return true;
  });
  if (!redeemed) {
    await _json(request, HttpStatus.notFound, {
      'success': false,
      'error': 'This invite link is invalid, expired, or revoked',
    });
    return;
  }
  await _json(request, HttpStatus.ok, {
    'success': true,
    'roomId': record.roomId,
    'action': record.joinMode,
  });
}

Future<void> _deleteInviteLinksForUser(String userId) async {
  await _withInviteStore((records) {
    records.removeWhere((_, record) {
      record.redeemedUserIds.remove(userId);
      return record.createdBy == userId;
    });
  });
}

void _inviteDisableCaching(HttpRequest request) {
  request.response.headers
    ..set(HttpHeaders.cacheControlHeader, 'no-store, max-age=0')
    ..set(HttpHeaders.pragmaHeader, 'no-cache')
    ..set('X-Content-Type-Options', 'nosniff');
}

Future<_InviteSession?> _inviteSession(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return null;
  }
  try {
    return _InviteSession(token, await _userDirectoryWhoami(token));
  } on _BadRequestException {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Invalid XMO session token',
    });
    return null;
  }
}

Future<_InviteRoom> _inviteLoadRoom(String roomId, String token) async {
  final base = Uri.parse(_userDirectoryConfig.homeserverUrl);
  final uri = base.replace(pathSegments: [
    '_matrix',
    'client',
    'v3',
    'rooms',
    roomId,
    'state',
  ]);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await req.close().timeout(const Duration(seconds: 15));
    final raw = await utf8.decoder.bind(response).join();
    if (response.statusCode == HttpStatus.forbidden ||
        response.statusCode == HttpStatus.notFound) {
      throw const _BadRequestException('Room is unavailable to this account');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const _BadRequestException('Could not verify room settings');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List)
      throw const _BadRequestException('Invalid room state');
    final events =
        decoded.map(_asMap).whereType<Map<String, dynamic>>().toList();
    return _InviteRoom.fromState(roomId, events);
  } finally {
    client.close(force: true);
  }
}

bool _inviteCanManage(_InviteRoom room, String userId) {
  if (room.memberships[userId] != 'join') return false;
  final userLevel = room.userPowerLevels[userId] ?? room.usersDefault;
  return userLevel >= 50;
}

String? _inviteJoinMode(_InviteRoom room) {
  if (!room.encrypted && room.joinRule == 'public') return 'join';
  if (room.encrypted &&
      (room.joinRule == 'knock' || room.joinRule == 'knock_restricted')) {
    return 'knock';
  }
  return null;
}

Future<_InviteRecord?> _inviteRecordForToken(String? token) async {
  if (token == null || !_inviteValidToken(token)) return null;
  return (await _readInviteRecords())[_inviteTokenHash(token)];
}

String? _inviteRoomId(Object? value) {
  final roomId = value?.toString().trim() ?? '';
  return roomId.startsWith('!') && roomId.contains(':') ? roomId : null;
}

String? _inviteOptionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _inviteBoundedInt(Object? value, {required int min, required int max}) {
  if (value == null) return null;
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed < min || parsed > max) {
    throw _BadRequestException('Value must be between $min and $max');
  }
  return parsed;
}

String _inviteRandomToken() => _inviteRandomId(32);
String _inviteRandomId(int byteCount) => base64Url
    .encode(List<int>.generate(byteCount, (_) => _random.nextInt(256)))
    .replaceAll('=', '');
String _inviteTokenHash(String token) =>
    sha256.convert(utf8.encode(token)).toString();
bool _inviteValidToken(String token) =>
    RegExp(r'^[A-Za-z0-9_-]{40,64}$').hasMatch(token);

Future<_EncryptedInviteToken> _inviteEncryptToken(String token) async {
  final algorithm = cryptography.AesGcm.with256bits();
  final box = await algorithm.encrypt(
    utf8.encode(token),
    secretKey: cryptography.SecretKey(_inviteConfig.secretKeyBytes!),
  );
  return _EncryptedInviteToken(
    cipherText: base64UrlEncode(box.cipherText),
    nonce: base64UrlEncode(box.nonce),
    mac: base64UrlEncode(box.mac.bytes),
  );
}

Future<String?> _inviteDecryptToken(_EncryptedInviteToken encrypted) async {
  try {
    final bytes = await cryptography.AesGcm.with256bits().decrypt(
      cryptography.SecretBox(
        base64Url.decode(base64Url.normalize(encrypted.cipherText)),
        nonce: base64Url.decode(base64Url.normalize(encrypted.nonce)),
        mac: cryptography.Mac(
          base64Url.decode(base64Url.normalize(encrypted.mac)),
        ),
      ),
      secretKey: cryptography.SecretKey(_inviteConfig.secretKeyBytes!),
    );
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

Future<Map<String, _InviteRecord>> _readInviteRecords() async {
  if (_inviteConfig.dataFile.isEmpty) return Map.of(_inviteMemoryStore);
  final file = File(_inviteConfig.dataFile);
  if (!await file.exists()) return {};
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return {};
    final result = <String, _InviteRecord>{};
    decoded.forEach((key, value) {
      final map = _asMap(value);
      final record = map == null ? null : _InviteRecord.tryFromJson(map);
      if (record != null) result[key.toString()] = record;
    });
    return result;
  } catch (_) {
    return {};
  }
}

Future<T> _withInviteStore<T>(
  T Function(Map<String, _InviteRecord> records) operation,
) {
  final completer = Completer<T>();
  _inviteStoreTail = _inviteStoreTail.catchError((_) {}).then((_) async {
    try {
      final records = await _readInviteRecords();
      final result = operation(records);
      await _writeInviteRecords(records);
      completer.complete(result);
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  });
  return completer.future;
}

Future<void> _writeInviteRecords(Map<String, _InviteRecord> records) async {
  if (_inviteConfig.dataFile.isEmpty) {
    _inviteMemoryStore
      ..clear()
      ..addAll(records);
    return;
  }
  final file = File(_inviteConfig.dataFile);
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode(records.map(
    (key, value) => MapEntry(key, value.toJson()),
  )));
  if (await file.exists()) await file.delete();
  await temp.rename(file.path);
}

Future<void> _inviteUnavailable(HttpRequest request) => _json(
      request,
      HttpStatus.serviceUnavailable,
      {'success': false, 'error': 'Invite links are not configured'},
    );

class InviteConfig {
  const InviteConfig({
    required this.webBaseUrl,
    required this.dataFile,
    required this.secretKeyBytes,
    required this.homeserverUrl,
    required this.serverName,
    required this.mediaAccessToken,
  });

  factory InviteConfig.fromEnvironment(Map<String, String> env) {
    final webBaseUrl =
        (env['XMO_INVITE_WEB_BASE_URL'] ?? 'https://xmo.dpdns.org')
            .trim()
            .replaceAll(RegExp(r'/+$'), '');
    var dataFile = env['XMO_INVITE_DATA_FILE']?.trim() ?? '';
    final authDataFile = env['XMO_AUTH_DATA_FILE']?.trim() ?? '';
    if (dataFile.isEmpty && authDataFile.isNotEmpty) {
      final file = File(authDataFile);
      dataFile =
          '${file.parent.path}${Platform.pathSeparator}invite_links.json';
    }
    return InviteConfig(
      webBaseUrl: webBaseUrl,
      dataFile: dataFile,
      secretKeyBytes: _decodeInviteSecret(env['XMO_INVITE_TOKEN_SECRET']),
      homeserverUrl: (env['XMO_HOMESERVER_URL'] ?? '').trim(),
      serverName: (env['XMO_MATRIX_SERVER_NAME'] ?? '').trim(),
      mediaAccessToken: (env['XMO_SYNAPSE_ADMIN_TOKEN'] ?? '').trim(),
    );
  }

  final String webBaseUrl;
  final String dataFile;
  final List<int>? secretKeyBytes;
  final String homeserverUrl;
  final String serverName;
  final String mediaAccessToken;
  bool get isConfigured =>
      Uri.tryParse(webBaseUrl)?.hasScheme == true &&
      secretKeyBytes?.length == 32;
  bool get canProxyAvatars =>
      isConfigured &&
      Uri.tryParse(homeserverUrl)?.hasScheme == true &&
      serverName.isNotEmpty &&
      mediaAccessToken.isNotEmpty;

  static List<int>? _decodeInviteSecret(String? raw) {
    final value = raw?.trim() ?? '';
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      return [
        for (var i = 0; i < value.length; i += 2)
          int.parse(value.substring(i, i + 2), radix: 16)
      ];
    }
    try {
      final decoded = base64Url.decode(base64Url.normalize(value));
      return decoded.length == 32 ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class _InviteSession {
  const _InviteSession(this.token, this.userId);
  final String token;
  final String userId;
}

class _InviteRoom {
  const _InviteRoom({
    required this.name,
    required this.roomType,
    required this.avatarUrl,
    required this.topic,
    required this.memberCount,
    required this.encrypted,
    required this.joinRule,
    required this.memberships,
    required this.userPowerLevels,
    required this.usersDefault,
  });

  factory _InviteRoom.fromState(
      String roomId, List<Map<String, dynamic>> events) {
    Map<String, dynamic>? content(String type) {
      for (final event in events.reversed) {
        if (event['type'] == type && '${event['state_key'] ?? ''}'.isEmpty) {
          return _asMap(event['content']);
        }
      }
      return null;
    }

    final type = content('xmo.room.type') ?? const <String, dynamic>{};
    final isChannel = type['is_channel'] == true;
    final isGroup = type['is_group'] == true;
    if (!isChannel && !isGroup) {
      throw const _BadRequestException(
        'Invite links are available only for XMO groups and channels',
      );
    }
    final powers = content('m.room.power_levels') ?? const <String, dynamic>{};
    final memberships = <String, String>{};
    var memberCount = 0;
    for (final event in events) {
      if (event['type'] != 'm.room.member') continue;
      final userId = event['state_key']?.toString() ?? '';
      final membership =
          _asMap(event['content'])?['membership']?.toString() ?? '';
      if (userId.isNotEmpty) memberships[userId] = membership;
      if (membership == 'join') memberCount++;
    }
    final users = _asMap(powers['users']) ?? const <String, dynamic>{};
    return _InviteRoom(
      name:
          content('m.room.name')?['name']?.toString().trim().isNotEmpty == true
              ? content('m.room.name')!['name'].toString().trim()
              : 'XMO ${isChannel ? 'channel' : 'group'}',
      roomType: isChannel ? 'channel' : 'group',
      avatarUrl: _inviteOptionalText(
        content('m.room.avatar')?['url'],
      ),
      topic: _inviteOptionalText(
        content('m.room.topic')?['topic'],
      ),
      memberCount: memberCount,
      encrypted: content('m.room.encryption') != null,
      joinRule:
          content('m.room.join_rules')?['join_rule']?.toString() ?? 'invite',
      memberships: memberships,
      userPowerLevels: <String, int>{
        for (final entry in users.entries)
          entry.key: (entry.value as num?)?.toInt() ?? 0,
      },
      usersDefault: (powers['users_default'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final String roomType;
  final String? avatarUrl;
  final String? topic;
  final int memberCount;
  final bool encrypted;
  final String joinRule;
  final Map<String, String> memberships;
  final Map<String, int> userPowerLevels;
  final int usersDefault;
}

class _EncryptedInviteToken {
  const _EncryptedInviteToken(
      {required this.cipherText, required this.nonce, required this.mac});
  factory _EncryptedInviteToken.fromJson(Map<String, dynamic> json) =>
      _EncryptedInviteToken(
        cipherText: json['cipherText']?.toString() ?? '',
        nonce: json['nonce']?.toString() ?? '',
        mac: json['mac']?.toString() ?? '',
      );
  final String cipherText;
  final String nonce;
  final String mac;
  Map<String, dynamic> toJson() =>
      {'cipherText': cipherText, 'nonce': nonce, 'mac': mac};
}

class _InviteRecord {
  _InviteRecord({
    required this.tokenHash,
    required this.encryptedToken,
    required this.linkId,
    required this.roomId,
    required this.roomName,
    required this.roomType,
    required this.avatarUrl,
    required this.topic,
    required this.memberCount,
    required this.joinMode,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    required this.maxUses,
    required this.usedCount,
    required this.active,
    required this.redeemedUserIds,
  });

  static _InviteRecord? tryFromJson(Map<String, dynamic> json) {
    final tokenHash = json['tokenHash']?.toString() ?? '';
    final encrypted = _asMap(json['encryptedToken']);
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (tokenHash.isEmpty ||
        encrypted == null ||
        createdAt == null ||
        expiresAt == null) return null;
    return _InviteRecord(
      tokenHash: tokenHash,
      encryptedToken: _EncryptedInviteToken.fromJson(encrypted),
      linkId: json['linkId']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? '',
      roomName: json['roomName']?.toString() ?? 'XMO room',
      roomType: json['roomType']?.toString() == 'channel' ? 'channel' : 'group',
      avatarUrl: json['avatarUrl']?.toString(),
      topic: json['topic']?.toString(),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      joinMode: json['joinMode']?.toString() == 'knock' ? 'knock' : 'join',
      createdBy: json['createdBy']?.toString() ?? '',
      createdAt: createdAt,
      expiresAt: expiresAt,
      maxUses: (json['maxUses'] as num?)?.toInt(),
      usedCount: (json['usedCount'] as num?)?.toInt() ?? 0,
      active: json['active'] == true,
      redeemedUserIds: ((json['redeemedUserIds'] as List?) ?? const [])
          .map((e) => '$e')
          .toSet(),
    );
  }

  final String tokenHash;
  final _EncryptedInviteToken encryptedToken;
  final String linkId;
  final String roomId;
  String roomName;
  final String roomType;
  String? avatarUrl;
  String? topic;
  int memberCount;
  final String joinMode;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int? maxUses;
  int usedCount;
  bool active;
  final Set<String> redeemedUserIds;

  bool get canBeUsed =>
      active &&
      DateTime.now().toUtc().isBefore(expiresAt) &&
      (maxUses == null || usedCount < maxUses!);

  bool canBeUsedBy(String userId) =>
      active &&
      DateTime.now().toUtc().isBefore(expiresAt) &&
      (redeemedUserIds.contains(userId) ||
          maxUses == null ||
          usedCount < maxUses!);

  void refreshRoomSnapshot(_InviteRoom room) {
    roomName = room.name;
    avatarUrl = room.avatarUrl;
    topic = room.topic;
    memberCount = room.memberCount;
  }

  Map<String, dynamic> toPublicJson() => {
        'linkId': linkId,
        'name': roomName,
        'type': roomType,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (joinMode == 'join' && topic != null) 'topic': topic,
        'memberCount': memberCount,
        'joinMode': joinMode,
        'expiresAt': expiresAt.toIso8601String(),
      };

  Map<String, dynamic> toOwnerJson(String token, String webBaseUrl) => {
        ...toPublicJson(),
        'url': '$webBaseUrl/join/$token',
        if (topic != null) 'topic': topic,
        'createdAt': createdAt.toIso8601String(),
        'usedCount': usedCount,
        if (maxUses != null) 'maxUses': maxUses,
        'active': active,
      };

  Map<String, dynamic> toJson() => {
        'tokenHash': tokenHash,
        'encryptedToken': encryptedToken.toJson(),
        'linkId': linkId,
        'roomId': roomId,
        'roomName': roomName,
        'roomType': roomType,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (topic != null) 'topic': topic,
        'memberCount': memberCount,
        'joinMode': joinMode,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        if (maxUses != null) 'maxUses': maxUses,
        'usedCount': usedCount,
        'active': active,
        'redeemedUserIds': redeemedUserIds.toList(),
      };
}
