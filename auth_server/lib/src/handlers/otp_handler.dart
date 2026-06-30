part of xmo_auth_server;

Future<void> _sendOtp(HttpRequest request) async {
  final body = await _readJson(request);
  final email = _normalizeEmail(body['email']);

  if (!_isValidEmail(email)) {
    await _json(request, HttpStatus.badRequest, {'error': 'Invalid email'});
    return;
  }

  if (_gmail.isEmpty || _gmailAppPassword.isEmpty) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Email credentials are not configured'},
    );
    return;
  }

  final otp = (_random.nextInt(900000) + 100000).toString();
  _otpStore[email] = _OtpRecord(
    code: otp,
    expiresAt: DateTime.now().toUtc().add(_otpTtl),
  );

  await _sendEmail(email, otp);
  stdout.writeln('OTP sent to $email');

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
    await _json(
      request,
      HttpStatus.tooManyRequests,
      {'error': 'Too many OTP attempts'},
    );
    return;
  }

  if (record.code != otp) {
    await _json(request, HttpStatus.badRequest, {'error': 'Incorrect OTP'});
    return;
  }

  _otpStore.remove(email);
  await _json(request, HttpStatus.ok, {'success': true});
}

Future<void> _sendEmail(String email, String otp) async {
  final smtpServer = gmail(_gmail, _gmailAppPassword);
  final message = Message()
    ..from = Address(_gmail, 'XMO Verification')
    ..recipients.add(email)
    ..subject = 'Your XMO verification code'
    ..html = '''
      <div style="font-family: Arial, sans-serif; text-align: center; padding: 24px;">
        <h2>Welcome to XMO</h2>
        <p>Your verification code is:</p>
        <h1 style="color: #9CFF2E; letter-spacing: 6px;">$otp</h1>
        <p>This code expires in 5 minutes.</p>
      </div>
    ''';

  await send(message, smtpServer);
}

String _normalizeEmail(Object? value) =>
    value?.toString().trim().toLowerCase() ?? '';

bool _isValidEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

class _OtpRecord {
  final String code;
  final DateTime expiresAt;
  int attempts = 0;

  _OtpRecord({
    required this.code,
    required this.expiresAt,
  });
}
