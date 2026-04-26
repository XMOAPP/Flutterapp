import 'dart:convert';
import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

// ============================================================================
// ⚠️ CONFIGURE YOUR GMAIL APP PASSWORD HERE
// ============================================================================
const String myGmail = 'sangeethkarunakaran16@gmail.com'; // <--- Enter your Gmail
const String myAppPassword = 'accuyaxisfvlzxfz'; // <--- Enter your 16-character App Password (no spaces)
// ============================================================================

void main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 3000);
  print('====================================================');
  print('✅ Local Email OTP Server running on http://localhost:3000');
  print('====================================================');
  print('Make sure you have updated myGmail and myAppPassword in email_server.dart!');

  await for (HttpRequest request in server) {
    // Enable CORS for Flutter Web
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.close();
      continue;
    }

    if (request.method == 'POST') {
      try {
        final content = await utf8.decoder.bind(request).join();
        final data = jsonDecode(content);
        final email = data['email'];
        final otp = data['otp'];

        print('Attempting to send OTP $otp to $email...');

        if (myGmail.contains('YOUR_EMAIL') || myAppPassword.contains('YOUR_16_CHAR')) {
           print('❌ ERROR: You must edit email_server.dart and add your Gmail credentials first!');
           request.response.statusCode = HttpStatus.internalServerError;
           request.response.write(jsonEncode({'error': 'Server credentials not configured'}));
           await request.response.close();
           continue;
        }

        final smtpServer = gmail(myGmail, myAppPassword);
        final message = Message()
          ..from = Address(myGmail, 'XMO Registration')
          ..recipients.add(email)
          ..subject = 'Your XMO Verification Code'
          ..html = '''
            <div style="font-family: sans-serif; text-align: center; padding: 20px;">
              <h2>Welcome to XMO!</h2>
              <p>Your verification code is:</p>
              <h1 style="color: #4CAF50; letter-spacing: 5px;">$otp</h1>
              <p>This code will expire in 5 minutes.</p>
            </div>
          ''';

        await send(message, smtpServer);
        print('✅ Email sent successfully to $email!');
        
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({'success': true}));
      } catch (e) {
        print('❌ Failed to send email: \$e');
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': e.toString()}));
      }
      await request.response.close();
    }
  }
}
