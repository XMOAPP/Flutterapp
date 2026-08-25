part of xmo_auth_server;

final _userDirectoryConfig = UserDirectoryConfig.fromEnvironment(
  Platform.environment,
);
final _userDirectoryMemoryStore = <String, _UserDirectoryEntry>{};

Future<void> _upsertUserDirectoryEntry(HttpRequest request) async {
  if (!_userDirectoryConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'User directory is not configured',
    });
    return;
  }

  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }

  final body = await _readJson(request);
  final userId = _userDirectoryNormalizeUserId(body['userId']);
  if (userId == null) {
    throw const _BadRequestException('Valid userId is required');
  }

  final whoamiUserId = await _userDirectoryWhoami(token);
  if (whoamiUserId != userId) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Token does not match user',
    });
    return;
  }

  final localpart = _userDirectoryLocalpartFromUserId(userId);
  final displayName = _userDirectoryFriendlyDisplayName(
    userId,
    _userDirectoryCleanText(body['displayName']) ??
        _userDirectoryCleanText(body['display_name']),
  );
  final avatarUrl =
      _userDirectoryCleanText(body['avatarUrl']) ??
      _userDirectoryCleanText(body['avatar_url']);

  final entries = await _readUserDirectoryEntries();
  entries[localpart] = _UserDirectoryEntry(
    userId: userId,
    localpart: localpart,
    displayName: displayName,
    avatarUrl: avatarUrl,
    isPublic: body['public'] == true,
    updatedAt: DateTime.now().toUtc(),
  );
  await _writeUserDirectoryEntries(entries);

  await _json(request, HttpStatus.ok, {
    'success': true,
    'userId': userId,
    'public': body['public'] == true,
  });
}

Future<void> _searchUserDirectory(HttpRequest request) async {
  if (!_userDirectoryConfig.isConfigured) {
    await _json(request, HttpStatus.ok, {
      'success': true,
      'results': <Map<String, dynamic>>[],
    });
    return;
  }

  final body = await _readJson(request);
  final query = body['query']?.toString().trim() ?? '';
  final localpart = _userDirectoryLocalpartFromExactAtQuery(query);
  if (localpart == null) {
    await _json(request, HttpStatus.ok, {
      'success': true,
      'results': <Map<String, dynamic>>[],
    });
    return;
  }

  final entry = (await _readUserDirectoryEntries())[localpart];
  if (entry == null || !entry.isPublic) {
    await _json(request, HttpStatus.ok, {
      'success': true,
      'results': <Map<String, dynamic>>[],
    });
    return;
  }

  await _json(request, HttpStatus.ok, {
    'success': true,
    'results': [entry.toPublicJson()],
  });
}

Future<String> _userDirectoryWhoami(String token) async {
  final base = Uri.parse(_userDirectoryConfig.homeserverUrl);
  final uri = base.replace(
    pathSegments: ['_matrix', 'client', 'v3', 'account', 'whoami'],
  );
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(const Duration(seconds: 15));
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const _BadRequestException('Invalid XMO session token');
    }
    final decoded = _decodeJsonMap(responseBody);
    final userId = decoded['user_id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw const _BadRequestException('Invalid XMO session response');
    }
    return userId;
  } finally {
    client.close(force: true);
  }
}

String? _userDirectoryBearerToken(HttpRequest request) {
  final header = request.headers.value(HttpHeaders.authorizationHeader);
  if (header == null) return null;
  final parts = header.split(' ');
  if (parts.length != 2 || parts.first.toLowerCase() != 'bearer') return null;
  final token = parts.last.trim();
  return token.isEmpty ? null : token;
}

Future<Map<String, _UserDirectoryEntry>> _readUserDirectoryEntries() async {
  if (_userDirectoryConfig.dataFile.isEmpty) {
    return Map<String, _UserDirectoryEntry>.from(_userDirectoryMemoryStore);
  }

  final file = File(_userDirectoryConfig.dataFile);
  if (!await file.exists()) return {};
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return {};
    final entries = <String, _UserDirectoryEntry>{};
    decoded.forEach((_, value) {
      final data = _asMap(value);
      if (data == null) return;
      final entry = _UserDirectoryEntry.tryFromJson(data);
      if (entry != null) entries[entry.localpart] = entry;
    });
    return entries;
  } catch (_) {
    return {};
  }
}

Future<void> _writeUserDirectoryEntries(
  Map<String, _UserDirectoryEntry> entries,
) async {
  if (_userDirectoryConfig.dataFile.isEmpty) {
    _userDirectoryMemoryStore
      ..clear()
      ..addAll(entries);
    return;
  }

  final file = File(_userDirectoryConfig.dataFile);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode(entries.map((key, value) => MapEntry(key, value.toJson()))),
  );
}

String? _userDirectoryNormalizeUserId(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (!raw.startsWith('@')) return null;
  final colon = raw.indexOf(':');
  if (colon <= 1 || colon == raw.length - 1) return null;
  final serverName = raw.substring(colon + 1).toLowerCase();
  if (serverName != _userDirectoryConfig.serverName.toLowerCase()) {
    return null;
  }
  final localpart = raw.substring(1, colon).toLowerCase();
  if (!_isValidMatrixLocalpart(localpart)) return null;
  return '@$localpart:${_userDirectoryConfig.serverName}';
}

String _userDirectoryLocalpartFromUserId(String userId) {
  final colon = userId.indexOf(':');
  return userId.substring(1, colon).toLowerCase();
}

String? _userDirectoryLocalpartFromExactAtQuery(String query) {
  final trimmed = query.trim().toLowerCase();
  if (!trimmed.startsWith('@')) return null;
  var value = trimmed.substring(1);
  final colon = value.indexOf(':');
  if (colon >= 0) {
    final serverName = value.substring(colon + 1);
    if (serverName != _userDirectoryConfig.serverName.toLowerCase()) {
      return null;
    }
    value = value.substring(0, colon);
  }
  if (!_isValidMatrixLocalpart(value)) return null;
  return value;
}

String? _userDirectoryCleanText(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text.length > 160 ? text.substring(0, 160) : text;
}

String _userDirectoryFriendlyDisplayName(String userId, String? candidate) {
  final value = candidate?.trim();
  final isFullUserId =
      value != null && RegExp(r'^@[^:\s]+:[^\s]+$').hasMatch(value);
  if (value != null && value.isNotEmpty && value != userId && !isFullUserId) {
    return value;
  }
  final localpart = _userDirectoryLocalpartFromUserId(userId);
  if (localpart.isEmpty) return 'Unknown';
  return '${localpart[0].toUpperCase()}${localpart.substring(1)}';
}

class UserDirectoryConfig {
  const UserDirectoryConfig({
    required this.homeserverUrl,
    required this.serverName,
    required this.dataFile,
  });

  factory UserDirectoryConfig.fromEnvironment(Map<String, String> env) {
    final homeserverUrl =
        env['XMO_HOMESERVER_URL'] ??
        env['MATRIX_HOMESERVER_URL'] ??
        'http://synapse:8008';
    final serverName =
        env['XMO_MATRIX_SERVER_NAME'] ??
        env['MATRIX_SERVER_NAME'] ??
        'localhost';
    final explicitDataFile = env['XMO_USER_DIRECTORY_DATA_FILE'];
    final authDataFile =
        env['XMO_AUTH_DATA_FILE'] ?? env['XMO_PASSWORD_RESET_DATA_FILE'] ?? '';

    var dataFile = explicitDataFile ?? '';
    if (dataFile.isEmpty && authDataFile.isNotEmpty) {
      final file = File(authDataFile);
      dataFile =
          '${file.parent.path}${Platform.pathSeparator}user_directory.json';
    }

    return UserDirectoryConfig(
      homeserverUrl: homeserverUrl,
      serverName: serverName,
      dataFile: dataFile,
    );
  }

  final String homeserverUrl;
  final String serverName;
  final String dataFile;

  bool get isConfigured =>
      homeserverUrl.trim().isNotEmpty && serverName.trim().isNotEmpty;
}

class _UserDirectoryEntry {
  const _UserDirectoryEntry({
    required this.userId,
    required this.localpart,
    required this.displayName,
    required this.avatarUrl,
    required this.isPublic,
    required this.updatedAt,
  });

  static _UserDirectoryEntry? tryFromJson(Map<String, dynamic> json) {
    final userId = json['userId']?.toString() ?? '';
    final localpart = json['localpart']?.toString() ?? '';
    if (userId.isEmpty || localpart.isEmpty) return null;
    return _UserDirectoryEntry(
      userId: userId,
      localpart: localpart,
      displayName: _userDirectoryFriendlyDisplayName(
        userId,
        json['displayName']?.toString(),
      ),
      avatarUrl: json['avatarUrl']?.toString(),
      isPublic: json['public'] == true,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String userId;
  final String localpart;
  final String displayName;
  final String? avatarUrl;
  final bool isPublic;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'localpart': localpart,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'public': isPublic,
    'updatedAt': updatedAt.toIso8601String(),
  };

  Map<String, dynamic> toPublicJson() => {
    'userId': userId,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
  };
}
