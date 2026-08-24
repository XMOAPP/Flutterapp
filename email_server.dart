import 'dart:convert';
import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

// Configure these with environment variables before running:
// $env:XMO_GMAIL='your-email@gmail.com'
// $env:XMO_GMAIL_APP_PASSWORD='your-16-character-app-password'
final String myGmail = Platform.environment['XMO_GMAIL'] ?? '';
final String myAppPassword =
    Platform.environment['XMO_GMAIL_APP_PASSWORD'] ?? '';
final Set<String> _allowedBrowserOrigins = _parseAllowedBrowserOrigins(
  Platform.environment['XMO_LOCAL_EMAIL_ALLOWED_CORS_ORIGINS'] ?? '',
);

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 3000);
  stdout.writeln('====================================================');
  stdout.writeln('Local Email OTP Server running on http://localhost:3000');
  stdout.writeln('====================================================');
  stdout.writeln(
    'Set XMO_GMAIL and XMO_GMAIL_APP_PASSWORD before sending OTPs.',
  );

  await for (final request in server) {
    final origin = request.headers.value('origin');
    if (origin != null && !_allowedBrowserOrigins.contains(origin)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      continue;
    }

    if (request.method == 'OPTIONS') {
      final requestedMethod = request.headers
          .value('access-control-request-method')
          ?.toUpperCase();
      final requestedHeaders = request.headers
          .value('access-control-request-headers')
          ?.split(',')
          .map((header) => header.trim().toLowerCase());
      final supportedHeaders =
          requestedHeaders == null ||
          requestedHeaders.every((header) => header == 'content-type');
      if (origin != null && (requestedMethod != 'POST' || !supportedHeaders)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        continue;
      }
      if (origin != null) _applyCorsHeaders(request.response, origin);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      continue;
    }

    if (origin != null) _applyCorsHeaders(request.response, origin);

    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      continue;
    }

    try {
      final content = await utf8.decoder.bind(request).join();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final email = data['email'] as String?;
      final otp = data['otp'] as String?;

      if (email == null || otp == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(jsonEncode({'error': 'Missing email or otp'}));
        await request.response.close();
        continue;
      }

      stdout.writeln('Attempting to send OTP $otp to $email...');

      if (myGmail.isEmpty || myAppPassword.isEmpty) {
        stderr.writeln(
          'ERROR: XMO_GMAIL and XMO_GMAIL_APP_PASSWORD must be set.',
        );
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(
          jsonEncode({'error': 'Server credentials not configured'}),
        );
        await request.response.close();
        continue;
      }

      final smtpServer = gmail(myGmail, myAppPassword);
      final message = Message()
        ..from = Address(myGmail, 'XMO Registration')
        ..recipients.add(email)
        ..subject = 'Your XMO Verification Code'
        ..html =
            '''
          <div style="font-family: sans-serif; text-align: center; padding: 20px;">
            <h2>Welcome to XMO!</h2>
            <p>Your verification code is:</p>
            <h1 style="color: #4CAF50; letter-spacing: 5px;">$otp</h1>
            <p>This code will expire in 5 minutes.</p>
          </div>
        ''';

      await send(message, smtpServer);
      stdout.writeln('Email sent successfully to $email.');

      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'success': true}));
    } catch (e) {
      stderr.writeln('Failed to send email: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': e.toString()}));
    }

    await request.response.close();
  }
}

Set<String> _parseAllowedBrowserOrigins(String rawOrigins) => rawOrigins
    .split(',')
    .map((origin) => origin.trim())
    .where((origin) => origin.isNotEmpty)
    .toSet();

void _applyCorsHeaders(HttpResponse response, String origin) {
  response.headers.set('Access-Control-Allow-Origin', origin);
  response.headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  response.headers.set('Vary', 'Origin');
}
