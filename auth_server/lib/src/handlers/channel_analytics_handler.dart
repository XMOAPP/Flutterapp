part of xmo_auth_server;

final _channelAnalyticsConfig =
    ChannelAnalyticsConfig.fromEnvironment(Platform.environment);
final _channelAnalyticsMemoryStore = <String, _StoredChannelPostAnalytics>{};
Future<void> _channelAnalyticsStoreTail = Future<void>.value();

Future<void> _recordChannelView(HttpRequest request) async {
  final auth = await _channelAnalyticsAuth(request);
  if (auth == null) return;
  final body = await _readJson(request);
  final roomId = _channelAnalyticsIdentifier(body['roomId'], '!');
  final eventId = _channelAnalyticsIdentifier(body['eventId'], r'$');
  if (roomId == null || eventId == null) {
    throw const _BadRequestException('Valid roomId and eventId are required');
  }
  if (!await _channelAnalyticsIsChannel(auth.token, roomId)) {
    throw const _BadRequestException('Room is not an XMO channel');
  }
  final event = await _channelAnalyticsEvent(auth.token, roomId, eventId);
  if (event == null || !_channelAnalyticsIsPost(event)) {
    throw const _BadRequestException('Channel post not found');
  }
  if (event['sender']?.toString() == auth.userId) {
    await _json(request, HttpStatus.ok, {'success': true, 'counted': false});
    return;
  }

  final viewerHash = _channelAnalyticsHash('viewer:${auth.userId}');
  final counted = await _withChannelAnalyticsStore((values) {
    final key = _channelAnalyticsPostKey(roomId, eventId);
    final post = values.putIfAbsent(
      key,
      () => _StoredChannelPostAnalytics(roomId: roomId, eventId: eventId),
    );
    final added = post.viewerHashes.add(viewerHash);
    if (added) post.updatedAt = DateTime.now().toUtc();
    return added;
  });
  await _json(request, HttpStatus.ok, {'success': true, 'counted': counted});
}

Future<void> _recordChannelForward(HttpRequest request) async {
  final auth = await _channelAnalyticsAuth(request);
  if (auth == null) return;
  final body = await _readJson(request);
  final roomId = _channelAnalyticsIdentifier(body['roomId'], '!');
  final eventId = _channelAnalyticsIdentifier(body['eventId'], r'$');
  final targetRoomId = _channelAnalyticsIdentifier(body['targetRoomId'], '!');
  final targetEventId =
      _channelAnalyticsIdentifier(body['targetEventId'], r'$');
  if (roomId == null ||
      eventId == null ||
      targetRoomId == null ||
      targetEventId == null) {
    throw const _BadRequestException('Invalid forward identifiers');
  }
  if (!await _channelAnalyticsIsChannel(auth.token, roomId)) {
    throw const _BadRequestException('Source room is not an XMO channel');
  }
  final source = await _channelAnalyticsEvent(auth.token, roomId, eventId);
  final target =
      await _channelAnalyticsEvent(auth.token, targetRoomId, targetEventId);
  if (source == null || !_channelAnalyticsIsPost(source) || target == null) {
    throw const _BadRequestException('Forwarded event could not be verified');
  }
  if (target['sender']?.toString() != auth.userId) {
    throw const _BadRequestException('Forwarded event sender is invalid');
  }

  // In encrypted destination rooms the forwarding marker is inside the
  // ciphertext. Synapse can verify the event and sender, but not its content.
  final targetIsEncrypted = target['type']?.toString() == 'm.room.encrypted';
  final content = _asMap(target['content']);
  final forwarded = _asMap(content?['xmo.forwarded']);
  if (!targetIsEncrypted &&
      (forwarded?['room_id']?.toString() != roomId ||
          forwarded?['event_id']?.toString() != eventId)) {
    throw const _BadRequestException('Target event is not this channel post');
  }

  final actorHash = _channelAnalyticsHash('actor:${auth.userId}');
  final actionHash = _channelAnalyticsHash(
    'forward:${auth.userId}:$targetRoomId',
  );
  final counted = await _withChannelAnalyticsStore((values) {
    final key = _channelAnalyticsPostKey(roomId, eventId);
    final post = values.putIfAbsent(
      key,
      () => _StoredChannelPostAnalytics(roomId: roomId, eventId: eventId),
    );
    if (post.forwardActions.containsKey(actionHash)) return false;
    post.forwardActions[actionHash] = actorHash;
    post.updatedAt = DateTime.now().toUtc();
    return true;
  });
  await _json(request, HttpStatus.ok, {'success': true, 'counted': counted});
}

Future<void> _getChannelAnalytics(HttpRequest request) async {
  final auth = await _channelAnalyticsAuth(request);
  if (auth == null) return;
  final body = await _readJson(request);
  final roomId = _channelAnalyticsIdentifier(body['roomId'], '!');
  if (roomId == null) throw const _BadRequestException('Valid roomId required');
  if (!await _canReviewRoomReports(
    token: auth.token,
    userId: auth.userId,
    roomId: roomId,
  )) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Channel administrator access required',
    });
    return;
  }
  if (!await _channelAnalyticsIsChannel(auth.token, roomId)) {
    throw const _BadRequestException('Room is not an XMO channel');
  }

  final requestedIds = <String>{};
  final rawIds = body['eventIds'];
  if (rawIds is List) {
    for (final value in rawIds.take(1000)) {
      final eventId = _channelAnalyticsIdentifier(value, r'$');
      if (eventId != null) requestedIds.add(eventId);
    }
  }
  final stored = await _readChannelAnalytics();
  final posts = <String, dynamic>{};
  final eventIds = requestedIds.isEmpty
      ? stored.values
          .where((post) => post.roomId == roomId)
          .map((post) => post.eventId)
          .toSet()
      : requestedIds;
  var totalViews = 0;
  for (final eventId in eventIds) {
    final post = stored[_channelAnalyticsPostKey(roomId, eventId)];
    final views = post?.viewerHashes.length ?? 0;
    final forwards = post?.forwardActions.length ?? 0;
    totalViews += views;
    posts[eventId] = {'views': views, 'forwards': forwards};
  }
  await _json(request, HttpStatus.ok, {
    'success': true,
    'posts': posts,
    'averageViews': eventIds.isEmpty ? 0 : totalViews / eventIds.length,
  });
}

Future<_ChannelAnalyticsAuth?> _channelAnalyticsAuth(
    HttpRequest request) async {
  if (!_channelAnalyticsConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Channel analytics is not configured',
    });
    return null;
  }
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing Matrix access token',
    });
    return null;
  }
  return _ChannelAnalyticsAuth(
    token: token,
    userId: await _userDirectoryWhoami(token),
  );
}

Future<Map<String, dynamic>?> _channelAnalyticsEvent(
  String token,
  String roomId,
  String eventId,
) async {
  final response = await _channelAnalyticsGet(
      token, ['_matrix', 'client', 'v3', 'rooms', roomId, 'event', eventId]);
  if (response == null) return null;
  return _decodeJsonMap(response);
}

Future<bool> _channelAnalyticsIsChannel(String token, String roomId) async {
  final typeRaw = await _channelAnalyticsGet(token, [
    '_matrix',
    'client',
    'v3',
    'rooms',
    roomId,
    'state',
    'xmo.room.type',
    ''
  ]);
  if (typeRaw != null) {
    final content = _decodeJsonMap(typeRaw);
    if (content['is_channel'] == true || content['kind'] == 'channel') {
      return true;
    }
    if (content['is_group'] == true || content['kind'] == 'group') return false;
  }
  final powerRaw = await _channelAnalyticsGet(token, [
    '_matrix',
    'client',
    'v3',
    'rooms',
    roomId,
    'state',
    'm.room.power_levels',
    ''
  ]);
  if (powerRaw == null) return false;
  final power = _decodeJsonMap(powerRaw);
  final eventsDefault = (power['events_default'] as num?)?.toInt() ?? 0;
  final usersDefault = (power['users_default'] as num?)?.toInt() ?? 0;
  return eventsDefault >= 50 && usersDefault == 0;
}

Future<String?> _channelAnalyticsGet(
    String token, List<String> pathSegments) async {
  final uri = Uri.parse(_channelAnalyticsConfig.homeserverUrl)
      .replace(pathSegments: pathSegments);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(const Duration(seconds: 12));
    final raw = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return raw;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

bool _channelAnalyticsIsPost(Map<String, dynamic> event) {
  final type = event['type']?.toString();
  return type == 'm.room.message' ||
      type == 'm.sticker' ||
      type == 'm.room.encrypted';
}

String? _channelAnalyticsIdentifier(Object? value, String prefix) {
  final text = value?.toString().trim();
  if (text == null || !text.startsWith(prefix) || text.length > 300)
    return null;
  return text;
}

String _channelAnalyticsPostKey(String roomId, String eventId) =>
    base64UrlEncode(utf8.encode('$roomId\n$eventId')).replaceAll('=', '');

String _channelAnalyticsHash(String value) {
  final hmac = Hmac(sha256, utf8.encode(_channelAnalyticsConfig.secret));
  return hmac.convert(utf8.encode(value)).toString();
}

Future<T> _withChannelAnalyticsStore<T>(
    T Function(Map<String, _StoredChannelPostAnalytics>) operation) {
  final completer = Completer<T>();
  _channelAnalyticsStoreTail = _channelAnalyticsStoreTail.then((_) async {
    try {
      final values = await _readChannelAnalytics();
      final result = operation(values);
      await _writeChannelAnalytics(values);
      completer.complete(result);
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  });
  return completer.future;
}

Future<Map<String, _StoredChannelPostAnalytics>> _readChannelAnalytics() async {
  if (_channelAnalyticsConfig.dataFile.isEmpty) {
    return Map.from(_channelAnalyticsMemoryStore);
  }
  final file = File(_channelAnalyticsConfig.dataFile);
  if (!await file.exists()) return {};
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return {};
    final result = <String, _StoredChannelPostAnalytics>{};
    for (final entry in decoded.entries) {
      final map = _asMap(entry.value);
      final value =
          map == null ? null : _StoredChannelPostAnalytics.fromJson(map);
      if (value != null) result[entry.key.toString()] = value;
    }
    return result;
  } catch (_) {
    return {};
  }
}

Future<void> _writeChannelAnalytics(
    Map<String, _StoredChannelPostAnalytics> values) async {
  if (_channelAnalyticsConfig.dataFile.isEmpty) {
    _channelAnalyticsMemoryStore
      ..clear()
      ..addAll(values);
    return;
  }
  final file = File(_channelAnalyticsConfig.dataFile);
  await file.parent.create(recursive: true);
  await file.writeAsString(
      jsonEncode(values.map((key, value) => MapEntry(key, value.toJson()))));
}

Future<void> _deleteChannelAnalyticsForUser(String userId) async {
  final viewerHash = _channelAnalyticsHash('viewer:$userId');
  final actorHash = _channelAnalyticsHash('actor:$userId');
  await _withChannelAnalyticsStore((values) {
    for (final post in values.values) {
      post.viewerHashes.remove(viewerHash);
      post.forwardActions.removeWhere((_, actor) => actor == actorHash);
    }
  });
}

class ChannelAnalyticsConfig {
  const ChannelAnalyticsConfig({
    required this.homeserverUrl,
    required this.dataFile,
    required this.secret,
  });

  factory ChannelAnalyticsConfig.fromEnvironment(Map<String, String> env) {
    final authData = env['XMO_AUTH_DATA_FILE'] ?? '';
    var dataFile = env['XMO_CHANNEL_ANALYTICS_DATA_FILE'] ?? '';
    if (dataFile.isEmpty && authData.isNotEmpty) {
      final file = File(authData);
      dataFile =
          '${file.parent.path}${Platform.pathSeparator}channel_analytics.json';
    }
    return ChannelAnalyticsConfig(
      homeserverUrl: env['XMO_HOMESERVER_URL'] ?? 'http://synapse:8008',
      dataFile: dataFile,
      secret: env['XMO_CHANNEL_ANALYTICS_SECRET'] ??
          env['XMO_WALLET_AUTH_SECRET'] ??
          '',
    );
  }

  final String homeserverUrl;
  final String dataFile;
  final String secret;
  bool get isConfigured => homeserverUrl.isNotEmpty && secret.length >= 32;
}

class _ChannelAnalyticsAuth {
  const _ChannelAnalyticsAuth({required this.token, required this.userId});
  final String token;
  final String userId;
}

class _StoredChannelPostAnalytics {
  _StoredChannelPostAnalytics({required this.roomId, required this.eventId});

  static _StoredChannelPostAnalytics? fromJson(Map<String, dynamic> json) {
    final roomId = json['roomId']?.toString();
    final eventId = json['eventId']?.toString();
    if (roomId == null || eventId == null) return null;
    final value = _StoredChannelPostAnalytics(roomId: roomId, eventId: eventId);
    value.viewerHashes.addAll(
      _asList(json['viewerHashes'])?.map((item) => '$item') ?? const [],
    );
    final forwards = _asMap(json['forwardActions']);
    if (forwards != null) {
      value.forwardActions
          .addAll(forwards.map((key, item) => MapEntry(key, item.toString())));
    }
    value.updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return value;
  }

  final String roomId;
  final String eventId;
  final Set<String> viewerHashes = {};
  final Map<String, String> forwardActions = {};
  DateTime updatedAt = DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'eventId': eventId,
        'viewerHashes': viewerHashes.toList(),
        'forwardActions': forwardActions,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
