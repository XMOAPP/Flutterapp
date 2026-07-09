import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'structured_logger.dart';

enum EmailProvider { brevo, gmail }

class EmailConfig {
  const EmailConfig({
    required this.provider,
    required this.brevoApiKey,
    required this.mailFrom,
    required this.mailFromName,
    required this.replyTo,
    required this.gmailUser,
    required this.gmailAppPassword,
    this.brevoEndpoint = 'https://api.brevo.com/v3/smtp/email',
  });

  factory EmailConfig.fromEnvironment(Map<String, String> env) {
    final providerValue = (env['EMAIL_PROVIDER'] ??
            (env['BREVO_API_KEY'] != null ? 'brevo' : 'gmail'))
        .trim()
        .toLowerCase();
    return EmailConfig(
      provider:
          providerValue == 'gmail' ? EmailProvider.gmail : EmailProvider.brevo,
      brevoApiKey: env['BREVO_API_KEY'] ?? '',
      mailFrom: env['MAIL_FROM'] ?? 'noreply@xmo.dpdns.org',
      mailFromName: env['MAIL_FROM_NAME'] ?? 'XMO',
      replyTo: env['MAIL_REPLY_TO'] ?? 'support@xmo.dpdns.org',
      gmailUser: env['EMAIL_USER'] ?? env['XMO_GMAIL'] ?? '',
      gmailAppPassword:
          env['EMAIL_APP_PASSWORD'] ?? env['XMO_GMAIL_APP_PASSWORD'] ?? '',
      brevoEndpoint:
          env['BREVO_ENDPOINT'] ?? 'https://api.brevo.com/v3/smtp/email',
    );
  }

  final EmailProvider provider;
  final String brevoApiKey;
  final String mailFrom;
  final String mailFromName;
  final String replyTo;
  final String gmailUser;
  final String gmailAppPassword;
  final String brevoEndpoint;

  bool get isBrevoConfigured => brevoApiKey.trim().isNotEmpty;

  bool get isGmailConfigured =>
      gmailUser.trim().isNotEmpty && gmailAppPassword.trim().isNotEmpty;

  bool get isConfigured =>
      provider == EmailProvider.brevo ? isBrevoConfigured : isGmailConfigured;
}

class EmailDeliveryException implements Exception {
  const EmailDeliveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EmailService {
  EmailService({
    required EmailConfig config,
    http.Client? httpClient,
    StructuredLogger logger = const StructuredLogger(),
    Duration requestTimeout = const Duration(seconds: 12),
    int maxAttempts = 3,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client(),
        _logger = logger,
        _requestTimeout = requestTimeout,
        _maxAttempts = maxAttempts.clamp(1, 5).toInt();

  final EmailConfig _config;
  final http.Client _httpClient;
  final StructuredLogger _logger;
  final Duration _requestTimeout;
  final int _maxAttempts;

  bool get isConfigured => _config.isConfigured;

  Future<void> sendOtpEmail({
    required String email,
    required String otp,
  }) {
    return sendGenericEmail(
      to: email,
      subject: 'Your XMO verification code',
      htmlContent: '''
        <div style="font-family: Arial, sans-serif; color: #111827; padding: 24px; line-height: 1.5; text-align: center;">
          <div style="max-width: 440px; margin: 0 auto;">
            <h2 style="margin: 0 0 16px;">Verify your XMO account</h2>
            <p style="margin: 0 0 12px;">You requested this code to verify your email address for XMO Messenger.</p>
            <p style="margin: 0 0 12px;">Enter this verification code in the XMO app:</p>
            <div style="font-size: 32px; font-weight: 700; color: #65C91A; letter-spacing: 6px; margin: 18px 0;">$otp</div>
            <p style="margin: 0 0 12px;">This code expires in 1 minute.</p>
            <p style="margin: 20px 0 0; color: #4B5563; font-size: 13px;">If you did not request this code, you can ignore this email.</p>
            <p style="margin: 12px 0 0; color: #4B5563; font-size: 13px;">XMO Messenger will never ask you to share this code with anyone.</p>
            <p style="margin: 16px 0 0; color: #4B5563; font-size: 13px;">Need help? Contact support@xmo.dpdns.org.</p>
          </div>
        </div>
      ''',
      textContent: 'Verify your XMO account\n\n'
          'You requested this code to verify your email address for XMO Messenger.\n\n'
          'Your verification code is: $otp\n\n'
          'This code expires in 1 minute.\n\n'
          'If you did not request this code, you can ignore this email. XMO Messenger will never ask you to share this code with anyone.\n\n'
          'Need help? Contact support@xmo.dpdns.org.',
      tag: 'otp',
    );
  }

  Future<void> sendPasswordResetEmail({
    required String email,
    required String resetLink,
  }) {
    return sendGenericEmail(
      to: email,
      subject: 'Reset your XMO password',
      htmlContent: '''
        <div style="font-family: Arial, sans-serif; padding: 24px;">
          <h2>Reset your XMO password</h2>
          <p>Use this link to reset your password:</p>
          <p><a href="$resetLink">$resetLink</a></p>
          <p>If you did not request this, you can ignore this email.</p>
        </div>
      ''',
      textContent:
          'Reset your XMO password using this link: $resetLink\n\nIf you did not request this, ignore this email.',
      tag: 'password-reset',
    );
  }

  Future<void> sendWelcomeEmail({
    required String email,
  }) {
    return sendGenericEmail(
      to: email,
      subject: 'Welcome to XMO',
      htmlContent: '''
        <div style="font-family: Arial, sans-serif; padding: 24px;">
          <h2>Welcome to XMO</h2>
          <p>Your XMO account is ready.</p>
        </div>
      ''',
      textContent: 'Welcome to XMO. Your account is ready.',
      tag: 'welcome',
    );
  }

  Future<void> sendGenericEmail({
    required String to,
    required String subject,
    required String htmlContent,
    String? textContent,
    String? toName,
    String? tag,
  }) async {
    if (!isConfigured) {
      throw const EmailDeliveryException('Email provider is not configured');
    }

    try {
      if (_config.provider == EmailProvider.brevo) {
        await _sendWithBrevo(
          to: to,
          subject: subject,
          htmlContent: htmlContent,
          textContent: textContent,
          toName: toName,
          tag: tag,
        );
      } else {
        await _sendWithGmail(
          to: to,
          subject: subject,
          htmlContent: htmlContent,
          textContent: textContent,
          toName: toName,
        );
      }
    } on EmailDeliveryException {
      rethrow;
    } catch (error, stackTrace) {
      _logger.error('email_send_failed', error, stackTrace);
      throw const EmailDeliveryException('Email delivery failed');
    }
  }

  Future<void> _sendWithBrevo({
    required String to,
    required String subject,
    required String htmlContent,
    String? textContent,
    String? toName,
    String? tag,
  }) async {
    final uri = Uri.parse(_config.brevoEndpoint);
    final body = <String, Object?>{
      'sender': {
        'name': _config.mailFromName,
        'email': _config.mailFrom,
      },
      'to': [
        {
          'email': to,
          if (toName != null && toName.trim().isNotEmpty) 'name': toName,
        }
      ],
      'replyTo': {
        'name': _config.mailFromName,
        'email': _config.replyTo,
      },
      'subject': subject,
      'htmlContent': htmlContent,
      if (textContent != null && textContent.trim().isNotEmpty)
        'textContent': textContent,
      if (tag != null && tag.trim().isNotEmpty) 'tags': [tag],
    };

    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final response = await _httpClient
            .post(
              uri,
              headers: {
                'accept': 'application/json',
                'api-key': _config.brevoApiKey,
                'content-type': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(_requestTimeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final responseBody = _decodeJsonMap(response.body);
          logInfo('email_sent', {
            'provider': 'brevo',
            'statusCode': response.statusCode,
            if (responseBody['messageId'] != null)
              'messageId': responseBody['messageId'],
            if (tag != null) 'tag': tag,
          });
          return;
        }

        if (!_shouldRetryStatus(response.statusCode) ||
            attempt == _maxAttempts) {
          logWarning('email_provider_rejected', {
            'provider': 'brevo',
            'statusCode': response.statusCode,
            if (tag != null) 'tag': tag,
          });
          throw EmailDeliveryException(
            'Brevo rejected email request with status ${response.statusCode}',
          );
        }
      } on TimeoutException catch (error, stackTrace) {
        if (attempt == _maxAttempts) {
          _logger.error('email_timeout', error, stackTrace);
          throw const EmailDeliveryException('Email provider timed out');
        }
      } on EmailDeliveryException {
        rethrow;
      } catch (error, stackTrace) {
        if (attempt == _maxAttempts) {
          _logger.error('email_provider_error', error, stackTrace);
          throw const EmailDeliveryException('Email provider request failed');
        }
      }

      await Future<void>.delayed(_retryDelay(attempt));
    }
  }

  Future<void> _sendWithGmail({
    required String to,
    required String subject,
    required String htmlContent,
    String? textContent,
    String? toName,
  }) async {
    final smtpServer = gmail(_config.gmailUser, _config.gmailAppPassword);
    final message = Message()
      ..from = Address(_config.gmailUser, _config.mailFromName)
      ..recipients.add(Address(to, toName))
      ..subject = subject
      ..html = htmlContent
      ..headers['reply-to'] = Address(_config.replyTo, _config.mailFromName);

    if (textContent != null && textContent.trim().isNotEmpty) {
      message.text = textContent;
    }

    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        await send(message, smtpServer).timeout(_requestTimeout);
        logInfo('email_sent', {'provider': 'gmail'});
        return;
      } on TimeoutException catch (error, stackTrace) {
        if (attempt == _maxAttempts) {
          _logger.error('email_timeout', error, stackTrace);
          throw const EmailDeliveryException('Email provider timed out');
        }
      } catch (error, stackTrace) {
        if (attempt == _maxAttempts) {
          _logger.error('email_provider_error', error, stackTrace);
          throw const EmailDeliveryException('Email provider request failed');
        }
      }

      await Future<void>.delayed(_retryDelay(attempt));
    }
  }

  bool _shouldRetryStatus(int statusCode) =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  Duration _retryDelay(int attempt) =>
      Duration(milliseconds: 250 * (1 << (attempt - 1)));

  Map<String, dynamic> _decodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return const {};
    }
    return const {};
  }
}
