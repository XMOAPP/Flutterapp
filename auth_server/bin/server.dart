import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

final String _gmail = Platform.environment['XMO_GMAIL'] ?? '';
final String _gmailAppPassword =
    Platform.environment['XMO_GMAIL_APP_PASSWORD'] ?? '';
final int _port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;

final _otpStore = <String, _OtpRecord>{};
final _random = Random.secure();

const _otpTtl = Duration(minutes: 5);
const _maxAttempts = 5;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
  stdout.writeln('XMO auth server listening on 0.0.0.0:$_port');

  await for (final request in server) {
    await _handleRequest(request);
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  _setCorsHeaders(request.response);

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  try {
    if (request.method == 'GET' && request.uri.path == '/health') {
      await _json(request, HttpStatus.ok, {'ok': true});
      return;
    }

    if (request.method == 'POST' && _isSendPath(request.uri.path)) {
      await _sendOtp(request);
      return;
    }

    if (request.method == 'POST' && _isVerifyPath(request.uri.path)) {
      await _verifyOtp(request);
      return;
    }

    await _json(request, HttpStatus.notFound, {'error': 'Not found'});
  } catch (e, st) {
    stderr.writeln('Request failed: $e\n$st');
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Internal server error'},
    );
  }
}

bool _isSendPath(String path) =>
    path == '/' || path == '/send' || path == '/auth/otp/send';

bool _isVerifyPath(String path) =>
    path == '/verify' || path == '/auth/otp/verify';

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

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  final content = await utf8.decoder.bind(request).join();
  if (content.trim().isEmpty) return {};
  return jsonDecode(content) as Map<String, dynamic>;
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

void _setCorsHeaders(HttpResponse response) {
  response.headers.add('Access-Control-Allow-Origin', '*');
  response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
}

Future<void> _json(
  HttpRequest request,
  int statusCode,
  Map<String, dynamic> body,
) async {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

class _OtpRecord {
  final String code;
  final DateTime expiresAt;
  int attempts = 0;

  _OtpRecord({
    required this.code,
    required this.expiresAt,
  });
}
