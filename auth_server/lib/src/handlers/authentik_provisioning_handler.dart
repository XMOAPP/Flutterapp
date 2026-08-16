part of xmo_auth_server;

final _authentikConfig =
    AuthentikProvisioningConfig.fromEnvironment(Platform.environment);

/// Performs an early registration check so an unavailable username is
/// rejected before an email OTP is sent. Registration repeats these checks
/// transactionally because availability can change after this response.
Future<void> _checkOidcUsernameAvailability(HttpRequest request) async {
  if (!_authentikConfig.isConfigured || !_passwordResetConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Account registration is not configured',
    });
    return;
  }

  final body = await _readJson(request);
  final username = _normalizeMatrixLocalpart(body['username']);
  if (username.isEmpty || !_isValidNewXmoUsername(username)) {
    throw const _BadRequestException('Invalid username');
  }

  final authentikUser = await _authentikFindUser(username);
  final walletUsernameTaken = _walletAccountStoreReady &&
      await _walletAccountStore.usernameExists(username);
  final matrixResponse = await _synapseRequest(
    method: 'GET',
    pathSegments: [
      '_synapse',
      'admin',
      'v2',
      'users',
      _matrixUserId(username),
    ],
  );
  if (matrixResponse.statusCode != HttpStatus.ok &&
      matrixResponse.statusCode != HttpStatus.notFound) {
    throw HttpException(
      'Synapse user lookup failed: ${matrixResponse.statusCode}',
    );
  }

  await _json(request, HttpStatus.ok, {
    'success': true,
    'available': !walletUsernameTaken &&
        authentikUser == null &&
        matrixResponse.statusCode == HttpStatus.notFound,
  });
}

/// Creates the complete OIDC account pair after email verification. Authentik
/// owns credentials; Synapse receives a passwordless user linked to the stable
/// Authentik subject used by the OIDC provider.
Future<void> _registerOidcAccount(HttpRequest request) async {
  if (!_authentikConfig.isConfigured || !_passwordResetConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'configured': false,
      'error': 'OIDC account registration is not configured',
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

  if (username.isEmpty || !_isValidNewXmoUsername(username)) {
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
      'error': 'Email verification is required for registration',
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
      'username': username,
      'userId': _matrixUserId(username),
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

  _AuthentikUser? createdAuthentikUser;
  try {
    var authentikUser = await _authentikFindUser(username);
    if (authentikUser != null &&
        _normalizeEmail(authentikUser.email) != email) {
      throw const _AuthentikUsernameConflict();
    }
    if (authentikUser == null) {
      authentikUser = await _authentikCreateLocalUser(
        username: username,
        email: email,
        password: password,
        displayName: displayName,
      );
      createdAuthentikUser = authentikUser;
    } else {
      // XMO customer accounts must not have access to Authentik's user
      // dashboard. Existing accounts are corrected here during their next
      // supported XMO registration attempt.
      await _authentikUpdateXmoUser(
        user: authentikUser,
        email: email,
        displayName: displayName,
      );
    }
    if (authentikUser.uuid.isEmpty) {
      throw const FormatException(
        'Authentik user response is missing the stable UUID',
      );
    }

    // Persist recovery ownership before creating the Matrix identity. Once the
    // passwordless Matrix user exists, no fallible local write should be able
    // to leave it linked to an Authentik user that is then rolled back.
    await _rememberPasswordResetEmail(username: username, email: email);
    await _ensureOidcMatrixUser(
      username: username,
      email: email,
      displayName: displayName,
      externalId: authentikUser.uuid,
    );
    _completeEnrollmentProof(
      proof: enrollmentProof,
      record: claimedProof,
      username: username,
    );
    logInfo('oidc_account_registered', {'username': username});
    await _json(request, HttpStatus.ok, {
      'success': true,
      'username': username,
      'userId': _matrixUserId(username),
    });
  } on _AuthentikUsernameConflict {
    _restoreEnrollmentProof(enrollmentProof, claimedProof);
    await _json(request, HttpStatus.conflict, {
      'success': false,
      'error': 'Username already taken',
    });
  } catch (error, st) {
    _restoreEnrollmentProof(enrollmentProof, claimedProof);
    if (createdAuthentikUser != null) {
      await _authentikDeleteUserByPk(createdAuthentikUser.pk);
    }
    _logger.error('oidc_account_registration_failed', error, st);
    await _json(request, HttpStatus.badGateway, {
      'success': false,
      'error': 'Could not create the XMO account. Please retry.',
    });
  }
}

Future<void> _ensureOidcMatrixUser({
  required String username,
  required String email,
  required String displayName,
  required String externalId,
}) async {
  final userId = _matrixUserId(username);
  final getResponse = await _synapseRequest(
    method: 'GET',
    pathSegments: [
      '_synapse',
      'admin',
      'v2',
      'users',
      userId,
    ],
  );
  Map<String, dynamic>? existing;
  if (getResponse.statusCode == HttpStatus.ok) {
    existing = _decodeJsonMap(getResponse.body);
  } else if (getResponse.statusCode != HttpStatus.notFound) {
    throw HttpException(
      'Synapse user lookup failed: ${getResponse.statusCode}',
    );
  }

  final externalIds = <Map<String, String>>[];
  for (final item in _asList(existing?['external_ids']) ?? const []) {
    final value = _asMap(item);
    final provider = value?['auth_provider']?.toString() ?? '';
    final id = value?['external_id']?.toString() ?? '';
    if (provider.isEmpty || id.isEmpty) continue;
    if (provider == _authentikConfig.oidcProviderId && id != externalId) {
      throw const _AuthentikUsernameConflict();
    }
    if (provider == _authentikConfig.oidcProviderId) continue;
    externalIds.add({'auth_provider': provider, 'external_id': id});
  }
  externalIds.add({
    'auth_provider': _authentikConfig.oidcProviderId,
    'external_id': externalId,
  });

  await _synapseUpdateUser(userId, {
    'displayname': displayName,
    'admin': false,
    'deactivated': false,
    'threepids': _mergedThreepids(existing?['threepids'], email),
    'external_ids': externalIds,
  });
}

/// Provisions secure sign-in only after Matrix registration has succeeded.
/// Authorization requires both the new Matrix session and the one-use,
/// email-bound OTP proof issued during registration.
Future<void> _provisionSecureLogin(HttpRequest request) async {
  if (!_authentikConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
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
    logInfo('authentik_directory_provisioned', {'username': username});
    await _json(request, HttpStatus.ok, {
      'success': true,
      'configured': true,
      'username': username,
    });
  } on _AuthentikUsernameConflict {
    _restoreEnrollmentProof(enrollmentProof, claimedProof);
    await _json(request, HttpStatus.conflict, {
      'success': false,
      'configured': true,
      'error': 'Username already taken',
    });
  } catch (error, st) {
    _restoreEnrollmentProof(enrollmentProof, claimedProof);
    _logger.error('authentik_directory_provisioning_failed', error, st);
    await _json(request, HttpStatus.badGateway, {
      'success': false,
      'configured': true,
      'error': 'Could not prepare secure sign-in',
    });
  }
}

/// Creates the Authentik identity before the first Matrix SSO login. A fresh,
/// email-bound OTP proof is the authorization; no Matrix password session is
/// created or required by this registration path.
Future<void> _prepareSecureRegistration(HttpRequest request) async {
  if (!_authentikConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'configured': false,
      'error': 'Secure registration is not configured',
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
      'error': 'Email verification is required for secure registration',
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
    // A process may stop after Authentik creates the identity but before the
    // proof completion is persisted. A verified retry for the same email is
    // idempotent; it never changes the existing password or account details.
    final existing = await _authentikFindUser(username);
    if (existing != null) {
      if (_normalizeEmail(existing.email) != email) {
        _restoreEnrollmentProof(enrollmentProof, claimedProof);
        await _json(request, HttpStatus.conflict, {
          'success': false,
          'configured': true,
          'error': 'Username already taken',
        });
        return;
      }
      _completeEnrollmentProof(
        proof: enrollmentProof,
        record: claimedProof,
        username: username,
      );
      logInfo('authentik_secure_registration_resumed', {
        'username': username,
      });
      await _json(request, HttpStatus.ok, {
        'success': true,
        'configured': true,
        'username': username,
      });
      return;
    }

    await _authentikCreateLocalUser(
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
    logInfo('authentik_secure_registration_prepared', {
      'username': username,
    });
    await _json(request, HttpStatus.ok, {
      'success': true,
      'configured': true,
      'username': username,
    });
  } catch (error, st) {
    _restoreEnrollmentProof(enrollmentProof, claimedProof);
    _logger.error('authentik_secure_registration_failed', error, st);
    await _json(request, HttpStatus.badGateway, {
      'success': false,
      'configured': true,
      'error': 'Could not prepare secure registration',
    });
  }
}

Future<_AuthentikUser> _authentikCreateLocalUser({
  required String username,
  required String email,
  required String password,
  required String displayName,
}) async {
  final user = await _authentikCreateUser(
    username: username,
    email: email,
    displayName: displayName,
    path: _authentikConfig.userPath,
  );
  try {
    await _authentikSetPassword(user.pk, password);
    return user;
  } catch (_) {
    await _authentikDeleteUserByPk(user.pk);
    rethrow;
  }
}

Future<void> _authentikDeleteUserByPk(int userPk) async {
  try {
    final response = await _authentikRequest(
      method: 'DELETE',
      pathSegments: ['api', 'v3', 'core', 'users', userPk.toString()],
    );
    if (response.statusCode != HttpStatus.noContent) {
      logWarning('authentik_registration_rollback_failed', {
        'statusCode': response.statusCode,
      });
    }
  } catch (error) {
    logWarning('authentik_registration_rollback_failed', {
      'error': error.runtimeType.toString(),
    });
  }
}

Future<void> _authentikProvisionLocalUser({
  required String username,
  required String email,
  required String password,
  required String displayName,
}) async {
  final existing = await _authentikFindUser(username);
  if (existing != null) {
    final existingEmail = _normalizeEmail(existing.email);
    if (existingEmail.isNotEmpty && existingEmail != email) {
      throw const _AuthentikUsernameConflict();
    }
    await _authentikRequest(
      method: 'PATCH',
      pathSegments: ['api', 'v3', 'core', 'users', existing.pk.toString()],
      body: {
        'name': displayName,
        'email': email,
        'is_active': true,
      },
    );
    await _authentikSetPassword(existing.pk, password);
    return;
  }

  await _authentikCreateLocalUser(
    username: username,
    email: email,
    password: password,
    displayName: displayName,
  );
}

Future<_AuthentikUser> _authentikCreateUser({
  required String username,
  required String email,
  required String displayName,
  required String path,
}) async {
  final response = await _authentikRequest(
    method: 'POST',
    pathSegments: ['api', 'v3', 'core', 'users'],
    body: _authentikCreateUserBody(
      username: username,
      email: email,
      displayName: displayName,
      path: path,
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

Future<void> _authentikDeleteAccount(String username) async {
  if (!_authentikConfig.isConfigured) {
    throw StateError('Authentik account deletion is not configured');
  }
  final user = await _authentikFindUser(username);
  if (user == null) return;

  await _authentikRevokeSessions(username);
  final response = await _authentikRequest(
    method: 'DELETE',
    pathSegments: ['api', 'v3', 'core', 'users', user.pk.toString()],
  );
  if (response.statusCode != HttpStatus.noContent &&
      response.statusCode != HttpStatus.notFound) {
    throw HttpException(
      'Authentik user deletion failed: ${response.statusCode}',
    );
  }
}

Future<_AuthentikUser> _authentikEnsureUser({
  required String username,
  required String email,
  required String displayName,
}) async {
  final existing = await _authentikFindUser(username);
  if (existing != null) {
    final existingEmail = _normalizeEmail(existing.email);
    if (existingEmail.isNotEmpty && existingEmail != email) {
      throw const _AuthentikUsernameConflict();
    }
    await _authentikUpdateXmoUser(
      user: existing,
      email: email,
      displayName: displayName,
    );
    return existing;
  }

  return _authentikCreateUser(
    username: username,
    email: email,
    displayName: displayName,
    path: _authentikConfig.userPath,
  );
}

/// XMO end-user identities are external Authentik users. This prevents the
/// Authentik dashboard from being exposed when a customer reaches `/if/user/`.
Future<void> _authentikUpdateXmoUser({
  required _AuthentikUser user,
  required String email,
  required String displayName,
}) async {
  final response = await _authentikRequest(
    method: 'PATCH',
    pathSegments: ['api', 'v3', 'core', 'users', user.pk.toString()],
    body: {
      'name': displayName,
      'email': email,
      'is_active': true,
      'type': 'external',
    },
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Authentik user update failed: ${response.statusCode}',
    );
  }
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
    // External users cannot browse Authentik's dashboard. Authentik remains
    // the credential provider, but XMO is the only end-user interface.
    'type': 'external',
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

Future<void> _authentikRevokeSessions(String username) async {
  if (!_authentikConfig.isConfigured) return;
  final user = await _authentikFindUser(username);
  if (user == null) {
    throw StateError('Authentik user does not exist');
  }

  const pageSize = 100;
  var page = 1;
  final sessionIds = <String>[];
  while (true) {
    final response = await _authentikRequest(
      method: 'GET',
      pathSegments: ['api', 'v3', 'core', 'authenticated_sessions'],
      queryParameters: {
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Authentik session lookup failed: ${response.statusCode}',
      );
    }

    final body = _decodeJsonMap(response.body);
    final results = _asList(body['results']) ?? const <dynamic>[];
    for (final item in results) {
      final session = _asMap(item);
      if (session == null ||
          session['user']?.toString() != user.pk.toString()) {
        continue;
      }
      final sessionId = session['uuid']?.toString() ?? '';
      if (sessionId.isNotEmpty) sessionIds.add(sessionId);
    }

    final pagination = _asMap(body['pagination']);
    final totalPages = int.tryParse(
          pagination?['total_pages']?.toString() ?? '',
        ) ??
        page;
    if (results.isEmpty || page >= totalPages) break;
    page += 1;
  }

  for (final sessionId in sessionIds) {
    final deleteResponse = await _authentikRequest(
      method: 'DELETE',
      pathSegments: [
        'api',
        'v3',
        'core',
        'authenticated_sessions',
        sessionId,
      ],
    );
    if (deleteResponse.statusCode != HttpStatus.noContent &&
        deleteResponse.statusCode != HttpStatus.notFound) {
      throw HttpException(
        'Authentik session revocation failed: ${deleteResponse.statusCode}',
      );
    }
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
    required this.oidcProviderId,
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
      oidcProviderId: env['XMO_AUTHENTIK_OIDC_PROVIDER_ID'] ?? 'oidc-authentik',
    );
  }

  final String baseUrl;
  final String apiToken;
  final String userPath;
  final String oidcProviderId;
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
  const _AuthentikUser({
    required this.pk,
    required this.username,
    required this.email,
    required this.uuid,
  });

  factory _AuthentikUser.fromJson(Map<String, dynamic> json) {
    final pk = json['pk'];
    if (pk is! num) {
      throw const FormatException('Authentik user response missing pk');
    }
    return _AuthentikUser(
      pk: pk.toInt(),
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      uuid: json['uuid']?.toString() ?? json['uid']?.toString() ?? '',
    );
  }

  final int pk;
  final String username;
  final String email;
  final String uuid;
}

class _AuthentikResponse {
  const _AuthentikResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class _AuthentikUsernameConflict implements Exception {
  const _AuthentikUsernameConflict();
}
