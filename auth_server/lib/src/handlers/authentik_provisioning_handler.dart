part of xmo_auth_server;

final _authentikConfig =
    AuthentikProvisioningConfig.fromEnvironment(Platform.environment);

Future<void> _provisionSecureLogin(HttpRequest request) async {
  if (!_authentikConfig.isConfigured) {
    await _json(request, HttpStatus.ok, {
      'success': false,
      'configured': false,
      'error': 'Secure sign-in provisioning is not configured',
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
  final username = _normalizeMatrixLocalpart(body['username']);
  final email = _normalizeEmail(body['email']);
  final password = body['password']?.toString() ?? '';
  final enrollmentProof =
      body['secureLoginEnrollmentProof']?.toString().trim() ?? '';
  final displayName = _authentikDisplayName(
    body['displayName'] ?? body['display_name'],
    username,
  );

  if (username.isEmpty || !_isValidMatrixLocalpart(username)) {
    throw const _BadRequestException('Invalid username');
  }
  if (!_isValidEmail(email)) {
    throw const _BadRequestException('Invalid email');
  }
  if (password.length < 6) {
    throw const _BadRequestException('Password must be at least 6 characters');
  }
  if (enrollmentProof.isEmpty) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Email verification is required for secure sign-in',
    });
    return;
  }

  final whoamiUserId = await _userDirectoryWhoami(token);
  if (_userDirectoryLocalpartFromUserId(whoamiUserId) != username) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Token does not match user',
    });
    return;
  }

  final passwordUserId = await _verifyMatrixPassword(username, password);
  if (passwordUserId == null ||
      _userDirectoryLocalpartFromUserId(passwordUserId) != username) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'The XMO password could not be verified',
    });
    return;
  }

  if (_wasEnrollmentProofCompleted(
    proof: enrollmentProof,
    email: email,
    username: username,
  )) {
    await _json(request, HttpStatus.ok, {
      'success': true,
      'configured': true,
      'username': username,
    });
    return;
  }

  final claimedProof = _claimEnrollmentProof(
    proof: enrollmentProof,
    email: email,
  );
  if (claimedProof == null) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Email verification expired or was already used',
    });
    return;
  }

  try {
    await _authentikProvisionLocalUser(
      username: username,
      email: email,
      password: password,
      displayName: displayName,
    );
    _completeEnrollmentProof(
      proof: enrollmentProof,
      record: claimedProof,
      username: username,
    );
    await _json(request, HttpStatus.ok, {
      'success': true,
      'configured': true,
      'username': username,
    });
  } catch (error, st) {
    _restoreEnrollmentProof(enrollmentProof, claimedProof);
    _logger.error('authentik_provisioning_failed', error, st);
    await _json(request, HttpStatus.badGateway, {
      'success': false,
      'configured': true,
      'error': 'Could not prepare secure sign-in',
    });
  }
}

Future<String?> _verifyMatrixPassword(String username, String password) async {
  final homeserver = Uri.parse(_userDirectoryConfig.homeserverUrl);
  final loginUri = homeserver.replace(
    pathSegments: ['_matrix', 'client', 'v3', 'login'],
  );
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(loginUri);
    final payload = utf8.encode(jsonEncode({
      'type': 'm.login.password',
      'identifier': {
        'type': 'm.id.user',
        'user': username,
      },
      'password': password,
    }));
    request.headers.contentType = ContentType.json;
    request.contentLength = payload.length;
    request.add(payload);
    final response = await request.close().timeout(const Duration(seconds: 15));
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) return null;
    final login = _decodeJsonMap(responseBody);
    final userId = login['user_id']?.toString();
    final accessToken = login['access_token']?.toString();
    if (accessToken != null && accessToken.isNotEmpty) {
      await _logoutMatrixVerificationSession(homeserver, accessToken);
    }
    return userId;
  } finally {
    client.close(force: true);
  }
}

Future<void> _logoutMatrixVerificationSession(
  Uri homeserver,
  String accessToken,
) async {
  final logoutUri = homeserver.replace(
    pathSegments: ['_matrix', 'client', 'v3', 'logout'],
  );
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(logoutUri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $accessToken',
    );
    request.contentLength = 0;
    final response = await request.close().timeout(const Duration(seconds: 15));
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      logWarning('matrix_password_verification_logout_failed', {
        'statusCode': response.statusCode,
      });
    }
  } catch (error) {
    logWarning('matrix_password_verification_logout_failed', {
      'error': error.runtimeType.toString(),
    });
  } finally {
    client.close(force: true);
  }
}

Future<void> _authentikProvisionLocalUser({
  required String username,
  required String email,
  required String password,
  required String displayName,
}) async {
  final user = await _authentikEnsureUser(
    username: username,
    email: email,
    displayName: displayName,
  );
  await _authentikSetPassword(user.pk, password);
}

Future<void> _authentikSyncPassword({
  required String username,
  required String email,
  required String password,
}) async {
  if (!_authentikConfig.isConfigured) return;
  final user = await _authentikEnsureUser(
    username: username,
    email: email,
    displayName: _authentikDisplayName(null, username),
  );
  await _authentikSetPassword(user.pk, password);
}

Future<void> _authentikDeactivateUser(String username) async {
  if (!_authentikConfig.isConfigured) return;
  final user = await _authentikFindUser(username);
  if (user == null) return;
  await _authentikRequest(
    method: 'PATCH',
    pathSegments: ['api', 'v3', 'core', 'users', user.pk.toString()],
    body: {'is_active': false},
  );
}

Future<_AuthentikUser> _authentikEnsureUser({
  required String username,
  required String email,
  required String displayName,
}) async {
  final existing = await _authentikFindUser(username);
  if (existing != null) {
    await _authentikRequest(
      method: 'PATCH',
      pathSegments: ['api', 'v3', 'core', 'users', existing.pk.toString()],
      body: {
        'name': displayName,
        'email': email,
        'is_active': true,
      },
    );
    return existing;
  }

  final response = await _authentikRequest(
    method: 'POST',
    pathSegments: ['api', 'v3', 'core', 'users'],
    body: _authentikCreateUserBody(
      username: username,
      email: email,
      displayName: displayName,
      path: _authentikConfig.userPath,
    ),
  );
  if (response.statusCode == HttpStatus.created) {
    return _AuthentikUser.fromJson(_decodeJsonMap(response.body));
  }

  final fallbackPath = _authentikConfig.fallbackUserPath;
  if (fallbackPath != null && response.statusCode == HttpStatus.badRequest) {
    final fallbackResponse = await _authentikRequest(
      method: 'POST',
      pathSegments: ['api', 'v3', 'core', 'users'],
      body: _authentikCreateUserBody(
        username: username,
        email: email,
        displayName: displayName,
        path: fallbackPath,
      ),
    );
    if (fallbackResponse.statusCode == HttpStatus.created) {
      logInfo('authentik_user_create_path_fallback_used', {
        'username': username,
        'path': fallbackPath,
      });
      return _AuthentikUser.fromJson(_decodeJsonMap(fallbackResponse.body));
    }
    throw HttpException(
      'Authentik user create failed: '
      '${fallbackResponse.statusCode} ${_authentikSafeErrorBody(fallbackResponse.body)}',
    );
  }

  throw HttpException(
    'Authentik user create failed: '
    '${response.statusCode} ${_authentikSafeErrorBody(response.body)}',
  );
}

Map<String, dynamic> _authentikCreateUserBody({
  required String username,
  required String email,
  required String displayName,
  required String path,
}) {
  return {
    'username': username,
    'name': displayName,
    'email': email,
    'is_active': true,
    'path': path,
    'type': 'internal',
    'attributes': <String, dynamic>{
      'xmo_matrix_localpart': username,
    },
  };
}

Future<_AuthentikUser?> _authentikFindUser(String username) async {
  final response = await _authentikRequest(
    method: 'GET',
    pathSegments: ['api', 'v3', 'core', 'users'],
    queryParameters: {
      'username': username,
      'page_size': '2',
      'include_groups': 'false',
    },
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Authentik user lookup failed: ${response.statusCode}',
    );
  }
  final body = _decodeJsonMap(response.body);
  final results = _asList(body['results']) ?? const [];
  for (final item in results) {
    final data = _asMap(item);
    if (data == null) continue;
    if (_normalizeMatrixLocalpart(data['username']) == username) {
      return _AuthentikUser.fromJson(data);
    }
  }
  return null;
}

Future<void> _authentikSetPassword(int userPk, String password) async {
  final response = await _authentikRequest(
    method: 'POST',
    pathSegments: [
      'api',
      'v3',
      'core',
      'users',
      userPk.toString(),
      'set_password',
    ],
    body: {'password': password},
  );
  if (response.statusCode != HttpStatus.noContent) {
    throw HttpException(
      'Authentik password sync failed: ${response.statusCode}',
    );
  }
}

Future<_AuthentikResponse> _authentikRequest({
  required String method,
  required List<String> pathSegments,
  Map<String, String>? queryParameters,
  Map<String, dynamic>? body,
}) async {
  final base = Uri.parse(_authentikConfig.baseUrl);
  final normalizedPathSegments =
      pathSegments.last.isEmpty ? pathSegments : <String>[...pathSegments, ''];
  final uri = base.replace(
    pathSegments: normalizedPathSegments,
    queryParameters: queryParameters,
  );
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.openUrl(method, uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${_authentikConfig.apiToken}',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      final bodyBytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    final responseBody = await utf8.decoder.bind(response).join();
    return _AuthentikResponse(response.statusCode, responseBody);
  } finally {
    client.close(force: true);
  }
}

String _authentikDisplayName(Object? value, String username) {
  final displayName = value?.toString().trim() ?? '';
  if (displayName.isNotEmpty) return displayName;
  if (username.isEmpty) return username;
  return username[0].toUpperCase() + username.substring(1);
}

class AuthentikProvisioningConfig {
  const AuthentikProvisioningConfig({
    required this.baseUrl,
    required this.apiToken,
    required this.userPath,
  });

  factory AuthentikProvisioningConfig.fromEnvironment(
    Map<String, String> env,
  ) {
    final rawBaseUrl =
        env['XMO_AUTHENTIK_BASE_URL'] ?? env['AUTHENTIK_BASE_URL'] ?? '';
    final baseUrl = rawBaseUrl.endsWith('/')
        ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
        : rawBaseUrl;
    return AuthentikProvisioningConfig(
      baseUrl: baseUrl,
      apiToken:
          env['XMO_AUTHENTIK_API_TOKEN'] ?? env['AUTHENTIK_API_TOKEN'] ?? '',
      userPath: env['XMO_AUTHENTIK_USER_PATH'] ?? 'users',
    );
  }

  final String baseUrl;
  final String apiToken;
  final String userPath;
  String? get fallbackUserPath {
    final trimmed = userPath.trim();
    if (trimmed.isEmpty || trimmed.contains('/')) return null;
    return 'goauthentik.io/$trimmed';
  }

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && apiToken.trim().isNotEmpty;
}

String _authentikSafeErrorBody(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.length > 500 ? '${trimmed.substring(0, 500)}...' : trimmed;
}

class _AuthentikUser {
  const _AuthentikUser({required this.pk, required this.username});

  factory _AuthentikUser.fromJson(Map<String, dynamic> json) {
    final pk = json['pk'];
    if (pk is! num) {
      throw const FormatException('Authentik user response missing pk');
    }
    return _AuthentikUser(
      pk: pk.toInt(),
      username: json['username']?.toString() ?? '',
    );
  }

  final int pk;
  final String username;
}

class _AuthentikResponse {
  const _AuthentikResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
