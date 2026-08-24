part of xmo_auth_server;

Future<void> _startPasswordReset(HttpRequest request) async {
  final body = await _readJson(request);
  final username = _normalizeMatrixLocalpart(body['username']);
  final email = _normalizeEmail(body['email']);

  if (username.isEmpty || !_isValidMatrixLocalpart(username)) {
    await _json(request, HttpStatus.badRequest, {'error': 'Invalid username'});
    return;
  }
  if (!_isValidEmail(email)) {
    await _json(request, HttpStatus.badRequest, {'error': 'Invalid email'});
    return;
  }
  if (!_emailService.isConfigured) {
    await _json(request, HttpStatus.internalServerError, {
      'error': 'Email provider is not configured',
    });
    return;
  }
  if (!_passwordResetConfig.isConfigured) {
    await _json(request, HttpStatus.internalServerError, {
      'error': 'Password reset is not configured',
    });
    return;
  }

  final verified = await _isPasswordResetEmailVerified(
    username: username,
    email: email,
  );
  if (!verified) {
    await _json(request, HttpStatus.ok, {'success': true});
    return;
  }

  final otp = (_random.nextInt(900000) + 100000).toString();
  _passwordResetStore[_passwordResetKey(
    username,
    email,
  )] = _PasswordResetRecord(
    code: otp,
    expiresAt: DateTime.now().toUtc().add(_passwordResetTtl),
  );

  try {
    await _emailService.sendGenericEmail(
      to: email,
      subject: 'Reset your XMO password',
      htmlContent:
          '''
        <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; text-align: center;">
          <h2 style="margin: 0 0 16px;">Reset your XMO password</h2>
          <p style="margin: 0 0 14px;">Enter this code in XMO to reset your password.</p>
          <div style="font-size: 32px; font-weight: 700; color: #65C91A; letter-spacing: 6px; margin: 18px 0;">$otp</div>
          <p style="margin: 0 0 14px;">This code expires in 5 minutes.</p>
          <p style="color: #666; font-size: 13px;">If you did not request this, you can ignore this email.</p>
          <p style="color: #666; font-size: 13px;">Need help? Contact support@xmo.dpdns.org.</p>
        </div>
      ''',
      textContent:
          'Reset your XMO password\n\n'
          'Your reset code is: $otp\n\n'
          'This code expires in 5 minutes.\n\n'
          'If you did not request this, ignore this email.\n\n'
          'Need help? Contact support@xmo.dpdns.org.',
      tag: 'password-reset',
    );
  } on EmailDeliveryException catch (error) {
    await _json(request, HttpStatus.badGateway, {'error': error.message});
    return;
  }

  logInfo('password_reset_otp_sent', {
    'usernameHash': username.hashCode,
    'emailHash': email.hashCode,
  });
  await _json(request, HttpStatus.ok, {'success': true});
}

Future<void> _completePasswordReset(HttpRequest request) async {
  final body = await _readJson(request);
  final username = _normalizeMatrixLocalpart(body['username']);
  final email = _normalizeEmail(body['email']);
  final otp = body['otp']?.toString().trim() ?? '';
  final newPassword = body['newPassword']?.toString() ?? '';

  if (username.isEmpty || !_isValidMatrixLocalpart(username)) {
    await _json(request, HttpStatus.badRequest, {'error': 'Invalid username'});
    return;
  }
  if (!_isValidEmail(email)) {
    await _json(request, HttpStatus.badRequest, {'error': 'Invalid email'});
    return;
  }
  if (otp.length != 6) {
    await _json(request, HttpStatus.badRequest, {
      'error': 'Invalid reset code',
    });
    return;
  }
  final passwordError = PasswordPolicy.validationError(newPassword);
  if (passwordError != null) {
    await _json(request, HttpStatus.badRequest, {'error': passwordError});
    return;
  }
  if (!_passwordResetConfig.isConfigured) {
    await _json(request, HttpStatus.internalServerError, {
      'error': 'Password reset is not configured',
    });
    return;
  }

  final key = _passwordResetKey(username, email);
  final record = _passwordResetStore[key];
  if (record == null) {
    await _json(request, HttpStatus.badRequest, {
      'error': 'Reset not requested',
    });
    return;
  }
  if (DateTime.now().toUtc().isAfter(record.expiresAt)) {
    _passwordResetStore.remove(key);
    await _json(request, HttpStatus.badRequest, {
      'error': 'Reset code expired',
    });
    return;
  }
  record.attempts += 1;
  if (record.attempts > _maxAttempts) {
    _passwordResetStore.remove(key);
    await _json(request, HttpStatus.tooManyRequests, {
      'error': 'Too many reset attempts',
    });
    return;
  }
  if (record.code != otp) {
    await _json(request, HttpStatus.badRequest, {
      'error': 'Incorrect reset code',
    });
    return;
  }

  final verified = await _isPasswordResetEmailVerified(
    username: username,
    email: email,
  );
  if (!verified) {
    _passwordResetStore.remove(key);
    await _json(request, HttpStatus.forbidden, {
      'error': 'Email is not verified',
    });
    return;
  }

  if (!_passwordResetConfig.oidcOnlyAuthentication) {
    try {
      await _synapseResetPassword(_matrixUserId(username), newPassword);
    } catch (error, st) {
      _logger.error('password_reset_failed', error, st);
      await _json(request, HttpStatus.badGateway, {
        'error': 'Could not reset password',
      });
      return;
    }
  }

  try {
    await _authentikSyncPassword(
      username: username,
      email: email,
      password: newPassword,
    );
  } catch (error, st) {
    _logger.error('authentik_password_sync_failed', error, st);
    await _json(request, HttpStatus.badGateway, {
      'error': _passwordResetConfig.oidcOnlyAuthentication
          ? 'Could not update your password. Please retry.'
          : 'Password was updated, but secure sign-in synchronization failed. Retry with the same new password.',
    });
    return;
  }

  try {
    await _authentikRevokeSessions(username);
    await _synapseDeleteAllDevices(_matrixUserId(username));
  } catch (error, st) {
    _logger.error('password_reset_session_revocation_failed', error, st);
    await _json(request, HttpStatus.badGateway, {
      'error':
          'Password updated, but existing sessions could not be signed out. Retry with the same new password.',
    });
    return;
  }

  _passwordResetStore.remove(key);
  logInfo('password_reset_completed', {'usernameHash': username.hashCode});
  await _json(request, HttpStatus.ok, {'success': true});
}

Future<bool> _isPasswordResetEmailVerified({
  required String username,
  required String email,
}) async => _recoveryEmailStore.hasVerifiedEmail(username, email);

Future<Map<String, dynamic>> _synapseGetUser(String userId) async {
  final response = await _synapseRequest(
    method: 'GET',
    pathSegments: ['_synapse', 'admin', 'v2', 'users', userId],
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('Synapse user lookup failed: ${response.statusCode}');
  }
  return _decodeJsonMap(response.body);
}

Future<void> _synapseUpdateUser(
  String userId,
  Map<String, dynamic> body,
) async {
  final response = await _synapseRequest(
    method: 'PUT',
    pathSegments: ['_synapse', 'admin', 'v2', 'users', userId],
    body: body,
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('Synapse user update failed: ${response.statusCode}');
  }
}

Future<bool> _isRecoveryEmailAvailable({
  required String userId,
  required String email,
}) async {
  final response = await _synapseRequest(
    method: 'GET',
    pathSegments: [
      '_synapse',
      'admin',
      'v1',
      'threepid',
      'email',
      'users',
      email,
    ],
  );
  if (response.statusCode == HttpStatus.notFound) return true;
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException(
      'Synapse recovery email lookup failed: ${response.statusCode}',
    );
  }
  final owner = _decodeJsonMap(response.body)['user_id']?.toString() ?? '';
  return owner == userId;
}

Future<bool> _verifyCurrentMatrixPassword({
  required String userId,
  required String password,
}) async {
  final response = await _synapseRequest(
    method: 'POST',
    pathSegments: ['_matrix', 'client', 'v3', 'login'],
    includeAdminToken: false,
    body: {
      'type': 'm.login.password',
      'identifier': {'type': 'm.id.user', 'user': userId},
      'password': password,
    },
  );
  return response.statusCode >= 200 && response.statusCode < 300;
}

Future<void> _synapseResetPassword(String userId, String newPassword) async {
  final response = await _synapseRequest(
    method: 'POST',
    pathSegments: ['_synapse', 'admin', 'v1', 'reset_password', userId],
    body: {'new_password': newPassword, 'logout_devices': true},
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('Synapse reset failed: ${response.statusCode}');
  }
}

Future<void> _synapseDeleteAllDevices(String userId) async {
  final listResponse = await _synapseRequest(
    method: 'GET',
    pathSegments: ['_synapse', 'admin', 'v2', 'users', userId, 'devices'],
  );
  if (listResponse.statusCode < 200 || listResponse.statusCode >= 300) {
    throw HttpException(
      'Synapse device lookup failed: ${listResponse.statusCode}',
    );
  }

  final devices =
      _asList(_decodeJsonMap(listResponse.body)['devices']) ??
      const <dynamic>[];
  final deviceIds = devices
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map((device) => device['device_id']?.toString() ?? '')
      .where((deviceId) => deviceId.isNotEmpty)
      .toList(growable: false);
  if (deviceIds.isEmpty) return;

  final deleteResponse = await _synapseRequest(
    method: 'POST',
    pathSegments: [
      '_synapse',
      'admin',
      'v2',
      'users',
      userId,
      'delete_devices',
    ],
    body: {'devices': deviceIds},
  );
  if (deleteResponse.statusCode < 200 || deleteResponse.statusCode >= 300) {
    throw HttpException(
      'Synapse device revocation failed: ${deleteResponse.statusCode}',
    );
  }
}

Future<_SynapseResponse> _synapseRequest({
  required String method,
  required List<String> pathSegments,
  Map<String, String>? queryParameters,
  Map<String, dynamic>? body,
  bool includeAdminToken = true,
}) async {
  final base = Uri.parse(_passwordResetConfig.homeserverUrl);
  final uri = base.replace(
    pathSegments: pathSegments,
    queryParameters: queryParameters,
  );
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.openUrl(method, uri);
    if (includeAdminToken) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${_passwordResetConfig.adminToken}',
      );
    }
    request.headers.contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    final responseBody = await utf8.decoder.bind(response).join();
    return _SynapseResponse(response.statusCode, responseBody);
  } finally {
    client.close(force: true);
  }
}

/// XMO supports one recovery email. Replacing the email entries prevents a
/// superseded or legacy 3PID from remaining an alternate password-reset path
/// in a Synapse deployment that has its own email reset feature enabled.
List<Map<String, String>> _replacePasswordRecoveryEmailThreepids(
  Object? current,
  String email,
) {
  final remaining = <Map<String, String>>[];
  for (final item in _asList(current) ?? const []) {
    final data = _asMap(item);
    final medium = data?['medium']?.toString();
    final address = data?['address']?.toString();
    if (medium == null || address == null || medium == 'email') continue;
    remaining.add({'medium': medium, 'address': address});
  }
  remaining.add({'medium': 'email', 'address': email});
  return remaining;
}

String _passwordResetKey(String username, String email) => '$username|$email';

String _normalizeMatrixLocalpart(Object? value) {
  var raw = value?.toString().trim().toLowerCase() ?? '';
  if (raw.startsWith('@')) {
    raw = raw.substring(1);
    final colon = raw.indexOf(':');
    if (colon >= 0) raw = raw.substring(0, colon);
  }
  return raw;
}

bool _isValidMatrixLocalpart(String username) =>
    RegExp(r'^[a-z0-9._=\-/]+$').hasMatch(username);

/// New XMO accounts use a stricter portable subset. Keep the broader Matrix
/// localpart validation above for recovery/deletion of older accounts.
bool _isValidNewXmoUsername(String username) =>
    RegExp(r'^[a-z0-9]+$').hasMatch(username);

String _matrixUserId(String username) =>
    '@${_normalizeMatrixLocalpart(username)}:${_passwordResetConfig.serverName}';

class PasswordResetConfig {
  const PasswordResetConfig({
    required this.homeserverUrl,
    required this.serverName,
    required this.adminToken,
    required this.dataFile,
    required this.oidcOnlyAuthentication,
  });

  factory PasswordResetConfig.fromEnvironment(Map<String, String> env) {
    final homeserverUrl =
        env['XMO_HOMESERVER_URL'] ??
        env['MATRIX_HOMESERVER_URL'] ??
        'http://synapse:8008';
    final serverName =
        env['XMO_MATRIX_SERVER_NAME'] ??
        env['MATRIX_SERVER_NAME'] ??
        'localhost';
    final dataFile =
        env['XMO_AUTH_DATA_FILE'] ?? env['XMO_PASSWORD_RESET_DATA_FILE'] ?? '';
    return PasswordResetConfig(
      homeserverUrl: homeserverUrl,
      serverName: serverName,
      adminToken:
          env['XMO_SYNAPSE_ADMIN_TOKEN'] ?? env['SYNAPSE_ADMIN_TOKEN'] ?? '',
      dataFile: dataFile,
      oidcOnlyAuthentication:
          (env['XMO_OIDC_ONLY_AUTHENTICATION'] ?? '').toLowerCase() == 'true',
    );
  }

  final String homeserverUrl;
  final String serverName;
  final String adminToken;
  final String dataFile;
  final bool oidcOnlyAuthentication;

  bool get isConfigured =>
      homeserverUrl.trim().isNotEmpty &&
      serverName.trim().isNotEmpty &&
      adminToken.trim().isNotEmpty;

  File? get recoveryEmailStorageFile {
    final configured = Platform.environment['XMO_RECOVERY_EMAIL_STORE_FILE'];
    if (configured != null && configured.trim().isNotEmpty) {
      return File(configured.trim());
    }
    if (dataFile.trim().isNotEmpty) {
      return File('$dataFile.recovery-email');
    }
    return File('/app/data/recovery_emails.json');
  }
}

class _PasswordResetRecord {
  _PasswordResetRecord({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
  int attempts = 0;
}

class _SynapseResponse {
  const _SynapseResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
