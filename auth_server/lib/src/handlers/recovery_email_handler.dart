part of xmo_auth_server;

/// Starts the only recovery-email flow available for a local Matrix account:
/// a verified registration email is bound to a username that does not exist
/// yet. A raw email OTP is not enough; completion also requires a bearer token
/// for the newly-created Matrix account.
Future<void> _prepareLocalRecoveryEmailEnrollment(HttpRequest request) async {
  final body = await _readJson(request);
  final username = _normalizeMatrixLocalpart(body['username']);
  final email = _normalizeEmail(body['email']);
  final enrollmentProof =
      body['secureLoginEnrollmentProof']?.toString().trim() ?? '';

  if (!_isValidNewXmoUsername(username) || !_isValidEmail(email)) {
    throw const _BadRequestException('Invalid recovery email enrollment');
  }
  if (enrollmentProof.isEmpty ||
      !_secureLoginEnrollmentProofs.isPendingForEmail(
        proof: enrollmentProof,
        email: email,
      )) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Email verification expired. Request a new code.',
    });
    return;
  }
  if (!_passwordResetConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Recovery email enrollment is unavailable',
    });
    return;
  }

  // A ticket can only be prepared before the username exists. This prevents a
  // compromised existing session from enrolling an attacker-controlled email.
  final lookup = await _synapseRequest(
    method: 'GET',
    pathSegments: ['_synapse', 'admin', 'v2', 'users', _matrixUserId(username)],
  );
  if (lookup.statusCode == HttpStatus.ok) {
    await _json(request, HttpStatus.conflict, {
      'success': false,
      'error': 'Recovery email is already configured for this account',
    });
    return;
  }
  if (lookup.statusCode != HttpStatus.notFound) {
    throw HttpException('Synapse user lookup failed: ${lookup.statusCode}');
  }
  if (!await _isRecoveryEmailAvailable(
    userId: _matrixUserId(username),
    email: email,
  )) {
    await _json(request, HttpStatus.conflict, {
      'success': false,
      'error': 'This email is already used by another account',
    });
    return;
  }

  final ticket = _recoveryEmailStore.issueLocalEnrollment(
    username: username,
    email: email,
  );
  await _json(request, HttpStatus.ok, {
    'success': true,
    'localEnrollmentTicket': ticket,
    'expiresInSeconds': _secureLoginEnrollmentProofTtl.inSeconds,
  });
}

Future<void> _completeLocalRecoveryEmailEnrollment(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }
  final body = await _readJson(request);
  final ticket = body['localEnrollmentTicket']?.toString().trim() ?? '';
  if (ticket.isEmpty) {
    throw const _BadRequestException(
      'Missing recovery email enrollment ticket',
    );
  }

  final userId = await _userDirectoryWhoami(token);
  final username = _normalizeMatrixLocalpart(userId);
  final enrollment = _recoveryEmailStore.claimLocalEnrollment(
    ticket: ticket,
    username: username,
  );
  if (enrollment == null) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Recovery email enrollment expired. Register again.',
    });
    return;
  }

  try {
    // The account identity comes from whoami, never from the request body.
    final profile = await _synapseGetUser(userId);
    await _synapseUpdateUser(userId, {
      'threepids': _replacePasswordRecoveryEmailThreepids(
        profile['threepids'],
        enrollment.email,
      ),
    });
    _recoveryEmailStore.setVerified(
      username: username,
      email: enrollment.email,
    );
    logInfo('recovery_email_enrolled', {'usernameHash': username.hashCode});
    await _json(request, HttpStatus.ok, {'success': true});
  } catch (error, stackTrace) {
    // A transient Synapse failure must not burn a verified registration ticket.
    _recoveryEmailStore.restoreLocalEnrollment(
      ticket: ticket,
      record: enrollment,
    );
    _logger.error('recovery_email_enrollment_failed', error, stackTrace);
    await _json(request, HttpStatus.badGateway, {
      'success': false,
      'error':
          'Recovery email enrollment could not be completed. Please retry.',
    });
  }
}

/// Changes an already trusted recovery email. Possession of a Matrix session
/// alone is insufficient: confirmation codes are sent independently to both
/// the old and the new address.
Future<void> _startRecoveryEmailChange(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }
  final body = await _readJson(request);
  final newEmail = _normalizeEmail(body['email']);
  if (!_isValidEmail(newEmail)) {
    throw const _BadRequestException('Invalid email');
  }
  if (!_emailService.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Recovery email changes are unavailable',
    });
    return;
  }

  final userId = await _userDirectoryWhoami(token);
  final username = _normalizeMatrixLocalpart(userId);
  final currentEmail = _recoveryEmailStore.verifiedEmailFor(username);
  var legacyPasswordEnrollment = false;
  var effectiveCurrentEmail = currentEmail;
  if (effectiveCurrentEmail == null && _authentikConfig.isConfigured) {
    final authentikUser = await _authentikFindUser(username);
    effectiveCurrentEmail = _normalizeEmail(authentikUser?.email);
    if (effectiveCurrentEmail.isEmpty) effectiveCurrentEmail = null;
  }
  if (effectiveCurrentEmail == null) {
    final currentPassword = body['currentPassword']?.toString() ?? '';
    if (currentPassword.isEmpty ||
        !_passwordResetConfig.isConfigured ||
        _passwordResetConfig.oidcOnlyAuthentication ||
        !await _verifyCurrentMatrixPassword(
          userId: userId,
          password: currentPassword,
        )) {
      await _json(request, HttpStatus.forbidden, {
        'success': false,
        'error':
            'Current authentication is required to enroll a recovery email',
      });
      return;
    }
    effectiveCurrentEmail = newEmail;
    legacyPasswordEnrollment = true;
  }
  if (currentEmail != null &&
      !legacyPasswordEnrollment &&
      effectiveCurrentEmail == newEmail) {
    await _json(request, HttpStatus.ok, {'success': true, 'unchanged': true});
    return;
  }
  final verifiedCurrentEmail = effectiveCurrentEmail;
  if (!await _isRecoveryEmailAvailable(userId: userId, email: newEmail)) {
    await _json(request, HttpStatus.conflict, {
      'success': false,
      'error': 'This email is already used by another account',
    });
    return;
  }

  final issue = _recoveryEmailStore.issueChange(
    username: username,
    currentEmail: verifiedCurrentEmail,
    newEmail: newEmail,
  );
  try {
    await _emailService.sendGenericEmail(
      to: verifiedCurrentEmail,
      subject: 'Confirm your XMO recovery email change',
      htmlContent:
          '<p>A recovery-email change was requested for your XMO account.</p>'
          '<p>Enter this confirmation code in XMO: <strong>${issue.currentEmailCode}</strong></p>'
          '<p>This code expires in 5 minutes. If you did not request this, do not share it.</p>',
      textContent:
          'A recovery-email change was requested for your XMO account.\n\n'
          'Your current-email confirmation code is: ${issue.currentEmailCode}\n\n'
          'This code expires in 5 minutes. If you did not request this, do not share it.',
      tag: 'recovery-email-change-old',
    );
    await _emailService.sendGenericEmail(
      to: newEmail,
      subject: 'Verify your new XMO recovery email',
      htmlContent:
          '<p>Use this code to verify this recovery email for XMO: '
          '<strong>${issue.newEmailCode}</strong></p>'
          '<p>This code expires in 5 minutes.</p>',
      textContent:
          'Verify your new XMO recovery email.\n\n'
          'Your new-email confirmation code is: ${issue.newEmailCode}\n\n'
          'This code expires in 5 minutes.',
      tag: 'recovery-email-change-new',
    );
  } on EmailDeliveryException catch (error) {
    await _json(request, HttpStatus.badGateway, {
      'success': false,
      'error': error.message,
    });
    return;
  }

  logInfo('recovery_email_change_started', {'usernameHash': username.hashCode});
  await _json(request, HttpStatus.ok, {
    'success': true,
    'transactionId': issue.transactionId,
    'expiresInSeconds': _secureLoginEnrollmentProofTtl.inSeconds,
  });
}

Future<void> _confirmRecoveryEmailChange(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }
  final body = await _readJson(request);
  final transactionId = body['transactionId']?.toString().trim() ?? '';
  final currentEmailCode = body['currentEmailCode']?.toString().trim() ?? '';
  final newEmailCode = body['newEmailCode']?.toString().trim() ?? '';
  if (transactionId.isEmpty ||
      !RegExp(r'^\d{6}$').hasMatch(currentEmailCode) ||
      !RegExp(r'^\d{6}$').hasMatch(newEmailCode)) {
    throw const _BadRequestException('Invalid recovery email confirmation');
  }

  final userId = await _userDirectoryWhoami(token);
  final username = _normalizeMatrixLocalpart(userId);
  final newEmail = _recoveryEmailStore.claimChange(
    transactionId: transactionId,
    username: username,
    currentEmailCode: currentEmailCode,
    newEmailCode: newEmailCode,
  );
  if (newEmail == null) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Recovery email confirmation is invalid or expired',
    });
    return;
  }

  try {
    final profile = await _synapseGetUser(userId);
    await _synapseUpdateUser(userId, {
      'threepids': _replacePasswordRecoveryEmailThreepids(
        profile['threepids'],
        newEmail,
      ),
    });
    if (_authentikConfig.isConfigured) {
      final authentikUser = await _authentikFindUser(username);
      if (authentikUser != null) {
        final response = await _authentikRequest(
          method: 'PATCH',
          pathSegments: [
            'api',
            'v3',
            'core',
            'users',
            authentikUser.pk.toString(),
          ],
          body: {'email': newEmail},
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'Authentik recovery email update failed: ${response.statusCode}',
          );
        }
      }
    }
    _recoveryEmailStore.setVerified(username: username, email: newEmail);
    logInfo('recovery_email_changed', {'usernameHash': username.hashCode});
    await _json(request, HttpStatus.ok, {'success': true});
  } catch (error, stackTrace) {
    _logger.error('recovery_email_change_failed', error, stackTrace);
    await _json(request, HttpStatus.badGateway, {
      'success': false,
      'error': 'Recovery email could not be changed. Start a new request.',
    });
  }
}
