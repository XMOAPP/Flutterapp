import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xmo_auth_server/src/email_service.dart';

void main() {
  test('EmailConfig defaults to Brevo when BREVO_API_KEY is present', () {
    final config = EmailConfig.fromEnvironment({
      'BREVO_API_KEY': 'test-key',
      'MAIL_FROM': 'noreply@xmo.dpdns.org',
      'MAIL_FROM_NAME': 'XMO',
    });

    expect(config.provider, EmailProvider.brevo);
    expect(config.isConfigured, isTrue);
    expect(config.mailFrom, 'noreply@xmo.dpdns.org');
    expect(config.mailFromName, 'XMO');
  });

  test('EmailConfig supports Gmail fallback with new and legacy env names', () {
    final newConfig = EmailConfig.fromEnvironment({
      'EMAIL_PROVIDER': 'gmail',
      'EMAIL_USER': 'xmomessenger@gmail.com',
      'EMAIL_APP_PASSWORD': 'app-password',
    });
    final legacyConfig = EmailConfig.fromEnvironment({
      'EMAIL_PROVIDER': 'gmail',
      'XMO_GMAIL': 'legacy@gmail.com',
      'XMO_GMAIL_APP_PASSWORD': 'legacy-password',
    });

    expect(newConfig.isConfigured, isTrue);
    expect(newConfig.gmailUser, 'xmomessenger@gmail.com');
    expect(legacyConfig.isConfigured, isTrue);
    expect(legacyConfig.gmailUser, 'legacy@gmail.com');
  });

  test('sendOtpEmail posts Brevo transactional email payload', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response('{"messageId":"test-message"}', 201);
    });
    final service = EmailService(
      config: EmailConfig.fromEnvironment({
        'EMAIL_PROVIDER': 'brevo',
        'BREVO_API_KEY': 'test-key',
        'MAIL_FROM': 'noreply@xmo.dpdns.org',
        'MAIL_FROM_NAME': 'XMO',
        'MAIL_REPLY_TO': 'support@xmo.dpdns.org',
      }),
      httpClient: client,
      requestTimeout: const Duration(seconds: 1),
    );

    await service.sendOtpEmail(email: 'user@example.com', otp: '123456');

    expect(
      capturedRequest.url.toString(),
      'https://api.brevo.com/v3/smtp/email',
    );
    expect(capturedRequest.headers['api-key'], 'test-key');
    expect(capturedRequest.headers['content-type'], 'application/json');
    final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(body['sender'], {'name': 'XMO', 'email': 'noreply@xmo.dpdns.org'});
    expect(body['replyTo'], {'name': 'XMO', 'email': 'support@xmo.dpdns.org'});
    expect(body['to'], [
      {'email': 'user@example.com'},
    ]);
    expect(body['subject'], 'Your XMO verification code');
    expect(body['htmlContent'].toString(), contains('123456'));
    expect(body['htmlContent'].toString(), contains('text-align: center'));
    expect(body['htmlContent'].toString(), contains('expires in 5 minutes'));
    expect(body['textContent'].toString(), contains('XMO Messenger'));
    expect(body['textContent'].toString(), contains('expires in 5 minutes'));
    expect(body['textContent'].toString(), contains('support@xmo.dpdns.org'));
    expect(body['tags'], ['otp']);
  });

  test(
    'sendGenericEmail throws clear error when provider is not configured',
    () {
      final service = EmailService(
        config: EmailConfig.fromEnvironment({'EMAIL_PROVIDER': 'brevo'}),
        httpClient: MockClient((request) async => http.Response('{}', 201)),
      );

      expect(
        () => service.sendGenericEmail(
          to: 'user@example.com',
          subject: 'Test',
          htmlContent: '<p>Test</p>',
        ),
        throwsA(isA<EmailDeliveryException>()),
      );
    },
  );

  test(
    'sendGenericEmail fails without exposing Brevo API key in error',
    () async {
      final service = EmailService(
        config: EmailConfig.fromEnvironment({
          'EMAIL_PROVIDER': 'brevo',
          'BREVO_API_KEY': 'secret-test-key',
        }),
        httpClient: MockClient((request) async {
          return http.Response('{"message":"bad key"}', 401);
        }),
        requestTimeout: const Duration(seconds: 1),
        maxAttempts: 1,
      );

      await expectLater(
        service.sendGenericEmail(
          to: 'user@example.com',
          subject: 'Test',
          htmlContent: '<p>Test</p>',
        ),
        throwsA(
          predicate<EmailDeliveryException>(
            (error) => !error.toString().contains('secret-test-key'),
          ),
        ),
      );
    },
  );
}
