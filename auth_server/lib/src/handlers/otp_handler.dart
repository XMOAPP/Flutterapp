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

  final otp = (_random.nextInt(900000) + 100000).toString();
  _otpStore[email] = _OtpRecord(
    code: otp,
    expiresAt: DateTime.now().toUtc().add(_otpTtl),
  );

  try {
    await _emailService.sendOtpEmail(email: email, otp: otp);
  } on EmailDeliveryException catch (error) {
    await _json(request, HttpStatus.badGateway, {'error': error.message});
    return;
  }
  logInfo('otp_sent', {'emailHash': email.hashCode});

  await _json(request, HttpStatus.ok, {'success': true});
}

Future<void> _verifyOtp(HttpRequest request) async {
  final body = await _readJson(request);
  final email = _normalizeEmail(body['email']);
  final otp = body['otp']?.toString().trim() ?? '';

  final record = _otpStore[email];
  if (record == null) {
    await _json(request, HttpStatus.badRequest, {'error': 'OTP not requested'});
    return;
  }

  if (DateTime.now().toUtc().isAfter(record.expiresAt)) {
    _otpStore.remove(email);
    await _json(request, HttpStatus.badRequest, {'error': 'OTP expired'});
    return;
  }

  record.attempts += 1;
  if (record.attempts > _maxAttempts) {
    _otpStore.remove(email);
    await _json(request, HttpStatus.tooManyRequests, {
      'error': 'Too many OTP attempts',
    });
    return;
  }

  if (record.code != otp) {
    await _json(request, HttpStatus.badRequest, {'error': 'Incorrect OTP'});
    return;
  }

  _otpStore.remove(email);
  final enrollmentProof = _secureLoginEnrollmentProofs.issue(email);
  logInfo('otp_verified', {
    'emailHash': email.hashCode,
    'secureLoginEnrollmentProofIssued': true,
  });
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

class _OtpRecord {
  final String code;
  final DateTime expiresAt;
  int attempts = 0;

  _OtpRecord({required this.code, required this.expiresAt});
}
