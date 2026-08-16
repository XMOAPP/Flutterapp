part of xmo_auth_server;

Future<void> _linkPasswordResetEmail(HttpRequest request) async {
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
  if (!_passwordResetConfig.isConfigured) {
    await _json(request, HttpStatus.ok, {'success': false});
    return;
  }

  final userId = _matrixUserId(username);
  try {
    final profile = await _synapseGetUser(userId);
    final threepids = _mergedThreepids(profile['threepids'], email);
    await _synapseUpdateUser(userId, {'threepids': threepids});
    await _rememberPasswordResetEmail(username: username, email: email);
    await _json(request, HttpStatus.ok, {'success': true});
  } catch (error, st) {
    _logger.error('password_reset_link_email_failed', error, st);
    await _json(request, HttpStatus.ok, {'success': false});
  }
}

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
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Email provider is not configured'},
    );
    return;
  }
  if (!_passwordResetConfig.isConfigured) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Password reset is not configured'},
    );
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
  _passwordResetStore[_passwordResetKey(username, email)] =
      _PasswordResetRecord(
    code: otp,
    expiresAt: DateTime.now().toUtc().add(_passwordResetTtl),
  );

  try {
    await _emailService.sendGenericEmail(
      to: email,
      subject: 'Reset your XMO password',
      htmlContent: '''
        <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; text-align: center;">
          <h2 style="margin: 0 0 16px;">Reset your XMO password</h2>
          <p style="margin: 0 0 14px;">Enter this code in XMO to reset your password.</p>
          <div style="font-size: 32px; font-weight: 700; color: #65C91A; letter-spacing: 6px; margin: 18px 0;">$otp</div>
          <p style="margin: 0 0 14px;">This code expires in 5 minutes.</p>
          <p style="color: #666; font-size: 13px;">If you did not request this, you can ignore this email.</p>
          <p style="color: #666; font-size: 13px;">Need help? Contact support@xmo.dpdns.org.</p>
        </div>
      ''',
      textContent: 'Reset your XMO password\n\n'
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
    await _json(
        request, HttpStatus.badRequest, {'error': 'Invalid reset code'});
    return;
  }
  if (newPassword.length < 6) {
    await _json(
      request,
      HttpStatus.badRequest,
      {'error': 'Password must be at least 6 characters'},
    );
    return;
  }
  if (!_passwordResetConfig.isConfigured) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Password reset is not configured'},
    );
    return;
  }

  final key = _passwordResetKey(username, email);
  final record = _passwordResetStore[key];
  if (record == null) {
    await _json(
        request, HttpStatus.badRequest, {'error': 'Reset not requested'});
    return;
  }
  if (DateTime.now().toUtc().isAfter(record.expiresAt)) {
    _passwordResetStore.remove(key);
    await _json(
        request, HttpStatus.badRequest, {'error': 'Reset code expired'});
    return;
  }
  record.attempts += 1;
  if (record.attempts > _maxAttempts) {
    _passwordResetStore.remove(key);
    await _json(
      request,
      HttpStatus.tooManyRequests,
      {'error': 'Too many reset attempts'},
    );
    return;
  }
  if (record.code != otp) {
    await _json(
        request, HttpStatus.badRequest, {'error': 'Incorrect reset code'});
    return;
  }

  final verified = await _isPasswordResetEmailVerified(
    username: username,
    email: email,
  );
  if (!verified) {
    _passwordResetStore.remove(key);
    await _json(
        request, HttpStatus.forbidden, {'error': 'Email is not verified'});
    return;
  }

  if (!_passwordResetConfig.oidcOnlyAuthentication) {
    try {
      await _synapseResetPassword(_matrixUserId(username), newPassword);
    } catch (error, st) {
      _logger.error('password_reset_failed', error, st);
      await _json(
        request,
        HttpStatus.badGateway,
        {'error': 'Could not reset password'},
      );
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
    await _json(
      request,
      HttpStatus.badGateway,
      {
        'error': _passwordResetConfig.oidcOnlyAuthentication
            ? 'Could not update your password. Please retry.'
            : 'Password was updated, but secure sign-in synchronization failed. Retry with the same new password.',
      },
    );
    return;
  }

  try {
    await _authentikRevokeSessions(username);
    await _synapseDeleteAllDevices(_matrixUserId(username));
  } catch (error, st) {
    _logger.error('password_reset_session_revocation_failed', error, st);
    await _json(
      request,
      HttpStatus.badGateway,
      {
        'error':
            'Password updated, but existing sessions could not be signed out. Retry with the same new password.',
      },
    );
    return;
  }

  _passwordResetStore.remove(key);
  logInfo('password_reset_completed', {'usernameHash': username.hashCode});
  await _json(request, HttpStatus.ok, {'success': true});
}

Future<bool> _isPasswordResetEmailVerified({
  required String username,
  required String email,
}) async {
  final remembered = await _readRememberedPasswordResetEmails();
  if (remembered[username] == email) return true;

  try {
    final profile = await _synapseGetUser(_matrixUserId(username));
    final threepids = _asList(profile['threepids']) ?? const [];
    return threepids.any((item) {
      final data = _asMap(item);
      return data?['medium']?.toString() == 'email' &&
          _normalizeEmail(data?['address']) == email;
    });
  } catch (_) {
    return false;
  }
}

Future<void> _rememberPasswordResetEmail({
  required String username,
  required String email,
}) async {
  if (_passwordResetConfig.dataFile.isEmpty) return;
  final entries = await _readRememberedPasswordResetEmails();
  entries[username] = email;
  await _writeRememberedPasswordResetEmails(entries);
}

Future<void> _writeRememberedPasswordResetEmails(
  Map<String, String> entries,
) async {
  if (_passwordResetConfig.dataFile.isEmpty) return;
  final file = File(_passwordResetConfig.dataFile);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(entries));
}

Future<Map<String, String>> _readRememberedPasswordResetEmails() async {
  if (_passwordResetConfig.dataFile.isEmpty) return {};
  final file = File(_passwordResetConfig.dataFile);
  if (!await file.exists()) return {};
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return {};
    return decoded.map(
      (key, value) => MapEntry(
        _normalizeMatrixLocalpart(key),
        _normalizeEmail(value),
      ),
    )..removeWhere((key, value) => key.isEmpty || value.isEmpty);
  } catch (_) {
    return {};
  }
}

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

Future<void> _synapseResetPassword(String userId, String newPassword) async {
  final response = await _synapseRequest(
    method: 'POST',
    pathSegments: ['_synapse', 'admin', 'v1', 'reset_password', userId],
    body: {
      'new_password': newPassword,
      'logout_devices': true,
    },
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('Synapse reset failed: ${response.statusCode}');
  }
}

Future<void> _synapseDeleteAllDevices(String userId) async {
  final listResponse = await _synapseRequest(
    method: 'GET',
    pathSegments: [
      '_synapse',
      'admin',
      'v2',
      'users',
      userId,
      'devices',
    ],
  );
  if (listResponse.statusCode < 200 || listResponse.statusCode >= 300) {
    throw HttpException(
      'Synapse device lookup failed: ${listResponse.statusCode}',
    );
  }

  final devices = _asList(_decodeJsonMap(listResponse.body)['devices']) ??
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
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${_passwordResetConfig.adminToken}',
    );
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

List<Map<String, String>> _mergedThreepids(Object? current, String email) {
  final existing = <Map<String, String>>[];
  for (final item in _asList(current) ?? const []) {
    final data = _asMap(item);
    if (data == null) continue;
    final medium = data['medium']?.toString();
    final address = data['address']?.toString();
    if (medium == null || address == null) continue;
    if (medium == 'email' && _normalizeEmail(address) == email) {
      continue;
    }
    existing.add({'medium': medium, 'address': address});
  }
  existing.add({'medium': 'email', 'address': email});
  return existing;
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
    final homeserverUrl = env['XMO_HOMESERVER_URL'] ??
        env['MATRIX_HOMESERVER_URL'] ??
        'http://synapse:8008';
    final serverName = env['XMO_MATRIX_SERVER_NAME'] ??
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
}

class _PasswordResetRecord {
  _PasswordResetRecord({
    required this.code,
    required this.expiresAt,
  });

  final String code;
  final DateTime expiresAt;
  int attempts = 0;
}

class _SynapseResponse {
  const _SynapseResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
