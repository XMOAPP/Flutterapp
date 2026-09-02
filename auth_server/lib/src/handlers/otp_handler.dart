part of xmo_auth_server;

Future<void> _sendOtp(HttpRequest request) async {
  final body = await _readJson(request);
  final email = _normalizeEmail(body['email']);

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

  if (!await _consumeEmailOtpSendQuota(
    request,
    purpose: EmailOtpPurpose.registration,
    subject: email,
  )) {
    return;
  }

  final otp = (_random.nextInt(900000) + 100000).toString();
  try {
    await _emailOtpStore.issue(
      purpose: EmailOtpPurpose.registration,
      subject: email,
      code: otp,
      expiresAt: DateTime.now().toUtc().add(_otpTtl),
    );
  } catch (error, stackTrace) {
    _logger.error('registration_otp_issue_failed', error, stackTrace);
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Email verification is temporarily unavailable',
    });
    return;
  }

  try {
    await _emailService.sendOtpEmail(email: email, otp: otp);
  } on EmailDeliveryException catch (error) {
    await _removeEmailOtpChallenge(
      purpose: EmailOtpPurpose.registration,
      subject: email,
    );
    await _json(request, HttpStatus.badGateway, {'error': error.message});
    return;
  }
  logInfo('registration_otp_sent');

  await _json(request, HttpStatus.ok, {'success': true});
}

Future<void> _verifyOtp(HttpRequest request) async {
  final body = await _readJson(request);
  final email = _normalizeEmail(body['email']);
  final otp = body['otp']?.toString().trim() ?? '';

  if (!_isValidEmail(email) || !RegExp(r'^\d{6}$').hasMatch(otp)) {
    await _json(request, HttpStatus.badRequest, {'error': 'Invalid OTP'});
    return;
  }
  if (!await _consumeEmailOtpVerificationQuota(
    request,
    purpose: EmailOtpPurpose.registration,
  )) {
    return;
  }

  late final EmailOtpAttemptResult attempt;
  try {
    attempt = await _emailOtpStore.claimAttempt(
      purpose: EmailOtpPurpose.registration,
      subject: email,
      code: otp,
      maxAttempts: _maxAttempts,
      claimTtl: _emailOtpClaimTtl,
    );
  } catch (error, stackTrace) {
    _logger.error('registration_otp_claim_failed', error, stackTrace);
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Email verification is temporarily unavailable',
    });
    return;
  }

  switch (attempt.status) {
    case EmailOtpAttemptStatus.valid:
      break;
    case EmailOtpAttemptStatus.notRequested:
      await _json(request, HttpStatus.badRequest, {
        'error': 'OTP not requested',
      });
      return;
    case EmailOtpAttemptStatus.expired:
      await _json(request, HttpStatus.badRequest, {'error': 'OTP expired'});
      return;
    case EmailOtpAttemptStatus.tooManyAttempts:
      await _json(request, HttpStatus.tooManyRequests, {
        'error': 'Too many OTP attempts',
      });
      return;
    case EmailOtpAttemptStatus.incorrectCode:
      await _json(request, HttpStatus.badRequest, {'error': 'Incorrect OTP'});
      return;
    case EmailOtpAttemptStatus.alreadyProcessing:
      await _json(request, HttpStatus.conflict, {
        'error': 'OTP verification is already being processed',
      });
      return;
  }

  late final String enrollmentProof;
  try {
    await _emailOtpStore.remove(
      purpose: EmailOtpPurpose.registration,
      subject: email,
    );
    enrollmentProof = _secureLoginEnrollmentProofs.issue(email);
  } catch (error, stackTrace) {
    _logger.error(
      'registration_enrollment_proof_issue_failed',
      error,
      stackTrace,
    );
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Email verification is temporarily unavailable',
    });
    return;
  }
  logInfo('otp_verified', {'secureLoginEnrollmentProofIssued': true});
  await _json(request, HttpStatus.ok, {
    'success': true,
    'secureLoginEnrollmentProof': enrollmentProof,
    'secureLoginEnrollmentProofExpiresInSeconds':
        _secureLoginEnrollmentProofTtl.inSeconds,
  });
}

SecureLoginEnrollmentProofClaim? _claimEnrollmentProof({
  required String proof,
  required String email,
}) => _secureLoginEnrollmentProofs.claim(proof: proof, email: email);

void _restoreEnrollmentProof(
  String proof,
  SecureLoginEnrollmentProofClaim record,
) {
  _secureLoginEnrollmentProofs.restore(proof, record);
}

void _completeEnrollmentProof({
  required String proof,
  required SecureLoginEnrollmentProofClaim record,
  required String username,
}) {
  _secureLoginEnrollmentProofs.complete(
    proof: proof,
    claim: record,
    username: username,
  );
}

bool _wasEnrollmentProofCompleted({
  required String proof,
  required String email,
  required String username,
}) => _secureLoginEnrollmentProofs.wasCompleted(
  proof: proof,
  email: email,
  username: username,
);

String _normalizeEmail(Object? value) =>
    value?.toString().trim().toLowerCase() ?? '';

bool _isValidEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

Future<bool> _consumeEmailOtpSendQuota(
  HttpRequest request, {
  required EmailOtpPurpose purpose,
  required String subject,
}) async {
  if (!_emailOtpStoreReady) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Email verification is temporarily unavailable',
    });
    return false;
  }
  try {
    final targetDecision = await _emailOtpStore.consumeQuota(
      purpose: purpose,
      category: 'send-target',
      identifier: subject,
      limit: _emailOtpSendTargetLimit,
      window: _emailOtpQuotaWindow,
    );
    if (!targetDecision.allowed) {
      await _respondEmailOtpRateLimited(request, targetDecision.retryAfter);
      return false;
    }
    final ipDecision = await _emailOtpStore.consumeQuota(
      purpose: purpose,
      category: 'send-ip',
      identifier: resolveRequestClientAddress(
        request,
        trustedProxies: _trustedProxyConfig,
      ),
      limit: _emailOtpSendIpLimit,
      window: _emailOtpQuotaWindow,
    );
    if (!ipDecision.allowed) {
      await _respondEmailOtpRateLimited(request, ipDecision.retryAfter);
      return false;
    }
    return true;
  } catch (error, stackTrace) {
    _logger.error('email_otp_send_quota_failed', error, stackTrace);
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Email verification is temporarily unavailable',
    });
    return false;
  }
}

Future<bool> _consumeEmailOtpVerificationQuota(
  HttpRequest request, {
  required EmailOtpPurpose purpose,
}) async {
  if (!_emailOtpStoreReady) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Email verification is temporarily unavailable',
    });
    return false;
  }
  try {
    final decision = await _emailOtpStore.consumeQuota(
      purpose: purpose,
      category: 'verify-ip',
      identifier: resolveRequestClientAddress(
        request,
        trustedProxies: _trustedProxyConfig,
      ),
      limit: _emailOtpVerifyIpLimit,
      window: _emailOtpQuotaWindow,
    );
    if (!decision.allowed) {
      await _respondEmailOtpRateLimited(request, decision.retryAfter);
      return false;
    }
    return true;
  } catch (error, stackTrace) {
    _logger.error('email_otp_verify_quota_failed', error, stackTrace);
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Email verification is temporarily unavailable',
    });
    return false;
  }
}

Future<void> _respondEmailOtpRateLimited(
  HttpRequest request,
  Duration retryAfter,
) async {
  final retrySeconds = retryAfter.inSeconds.clamp(1, 3600);
  request.response.headers.set(HttpHeaders.retryAfterHeader, retrySeconds);
  await _json(request, HttpStatus.tooManyRequests, {
    'error': 'Too many verification requests. Please try again later.',
  });
}

Future<void> _removeEmailOtpChallenge({
  required EmailOtpPurpose purpose,
  required String subject,
}) async {
  if (!_emailOtpStoreReady) return;
  try {
    await _emailOtpStore.remove(purpose: purpose, subject: subject);
  } catch (error, stackTrace) {
    _logger.error('email_otp_challenge_remove_failed', error, stackTrace);
  }
}
