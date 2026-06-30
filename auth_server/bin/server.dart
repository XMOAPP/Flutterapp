library xmo_auth_server;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:googleapis_auth/auth_io.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'package:xmo_auth_server/src/endpoint_modules.dart';
import 'package:xmo_auth_server/src/health_status.dart';
import 'package:xmo_auth_server/src/request_guard.dart';
import 'package:xmo_auth_server/src/structured_logger.dart';

part '../lib/src/handlers/donation_handler.dart';
part '../lib/src/handlers/otp_handler.dart';
part '../lib/src/handlers/push_handler.dart';

final String _gmail = Platform.environment['XMO_GMAIL'] ?? '';
final String _gmailAppPassword =
    Platform.environment['XMO_GMAIL_APP_PASSWORD'] ?? '';
final int _port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;
final String _thirdwebSecretKey =
    Platform.environment['XMO_THIRDWEB_SECRET_KEY'] ?? '';
final String _donationRecipientAddress =
    Platform.environment['XMO_DONATION_RECIPIENT_ADDRESS'] ??
        _defaultDonationRecipientAddress;
final String _firebaseServiceAccountJson =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_JSON'] ?? '';
final String _firebaseServiceAccountBase64 =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_BASE64'] ?? '';
final String _firebaseServiceAccountFile =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_FILE'] ?? '';
final String _firebaseProjectId =
    Platform.environment['XMO_FIREBASE_PROJECT_ID'] ?? '';

final _otpStore = <String, _OtpRecord>{};
final _random = Random.secure();
final _rateLimiter = RequestRateLimiter();
const _logger = StructuredLogger();
const _otpEndpoints = OtpEndpointModule(send: _sendOtp, verify: _verifyOtp);
const _donationEndpoints = DonationEndpointModule(_createDonationPayment);
const _pushEndpoints = PushGatewayEndpointModule(_handleMatrixPush);

const _otpTtl = Duration(minutes: 5);
const _maxAttempts = 5;
const _thirdwebBaseUrl = 'https://api.thirdweb.com';
const _baseUsdcAddress = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _defaultDonationRecipientAddress =
    '0xc1a4BF16f64f5eE26b7C73831eF8bc70f200EacB';
const _baseChainId = 8453;
const _minDonationUsd = 5.0;
const _firebaseMessagingScope =
    'https://www.googleapis.com/auth/firebase.messaging';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
  stdout.writeln('XMO auth server listening on 0.0.0.0:$_port');

  await for (final request in server) {
    await _handleRequest(request);
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  final stopwatch = Stopwatch()..start();
  _setCorsHeaders(request.response);

  try {
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && !_rateLimiter.allow(request)) {
      await _json(request, HttpStatus.tooManyRequests, {
        'error': 'Too many requests. Please try again shortly.',
      });
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/health') {
      await _json(
        request,
        HttpStatus.ok,
        buildHealthStatus(
          emailConfigured: _gmail.isNotEmpty && _gmailAppPassword.isNotEmpty,
          donationConfigured: _thirdwebSecretKey.isNotEmpty &&
              _donationRecipientAddress.isNotEmpty,
          pushConfigured: _firebaseServiceAccountJson.isNotEmpty ||
              _firebaseServiceAccountBase64.isNotEmpty ||
              _firebaseServiceAccountFile.isNotEmpty,
        ),
      );
      return;
    }

    if (request.method == 'POST' &&
        _otpEndpoints.handlesSend(request.uri.path)) {
      await _otpEndpoints.send(request);
      return;
    }

    if (request.method == 'POST' &&
        _otpEndpoints.handlesVerify(request.uri.path)) {
      await _otpEndpoints.verify(request);
      return;
    }

    if (request.method == 'POST' &&
        _donationEndpoints.handles(request.uri.path)) {
      await _donationEndpoints.create(request);
      return;
    }

    if (request.method == 'POST' && _pushEndpoints.handles(request.uri.path)) {
      await _pushEndpoints.forward(request);
      return;
    }

    await _json(request, HttpStatus.notFound, {'error': 'Not found'});
  } on _BadRequestException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  } catch (e, st) {
    _logger.error('request_failed', e, st);
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Internal server error'},
    );
  } finally {
    stopwatch.stop();
    _logger.request(
      request: request,
      statusCode: request.response.statusCode,
      elapsed: stopwatch.elapsed,
    );
  }
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  const maxRequestBytes = 1024 * 1024;
  final contentLength = request.contentLength;
  if (contentLength > maxRequestBytes) {
    throw const _BadRequestException('Request body is too large');
  }
  final content = await utf8.decoder.bind(request).join();
  if (content.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const _BadRequestException('JSON object expected');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } on FormatException {
    throw const _BadRequestException('Invalid JSON request body');
  }
}

Map<String, dynamic> _decodeJsonMap(String body) {
  if (body.trim().isEmpty) return {};
  final decoded = jsonDecode(body);
  return decoded is Map<String, dynamic> ? decoded : {};
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<dynamic>? _asList(Object? value) => value is List ? value : null;

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

class _BadRequestException implements Exception {
  const _BadRequestException(this.message);
  final String message;
}
