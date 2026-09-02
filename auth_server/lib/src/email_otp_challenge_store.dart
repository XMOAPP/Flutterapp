import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

enum EmailOtpPurpose {
  registration('registration'),
  externalAccountDeletion('external_account_deletion'),
  passwordReset('password_reset');

  const EmailOtpPurpose(this.value);

  final String value;
}

class EmailOtpChallengeStoreConfig {
  const EmailOtpChallengeStoreConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.codeSecret,
  });

  factory EmailOtpChallengeStoreConfig.fromEnvironment(
    Map<String, String> env,
  ) {
    String value(
      String otpName,
      String resetName,
      String walletName,
      String fallback,
    ) {
      for (final name in [otpName, resetName, walletName]) {
        final configured = env[name]?.trim();
        if (configured != null && configured.isNotEmpty) return configured;
      }
      return fallback;
    }

    return EmailOtpChallengeStoreConfig(
      host: value(
        'XMO_EMAIL_OTP_DB_HOST',
        'XMO_PASSWORD_RESET_DB_HOST',
        'XMO_WALLET_DB_HOST',
        'postgres',
      ),
      port:
          int.tryParse(
            value(
              'XMO_EMAIL_OTP_DB_PORT',
              'XMO_PASSWORD_RESET_DB_PORT',
              'XMO_WALLET_DB_PORT',
              '5432',
            ),
          ) ??
          5432,
      database: value(
        'XMO_EMAIL_OTP_DB_NAME',
        'XMO_PASSWORD_RESET_DB_NAME',
        'XMO_WALLET_DB_NAME',
        'xmo_wallet',
      ),
      username: value(
        'XMO_EMAIL_OTP_DB_USER',
        'XMO_PASSWORD_RESET_DB_USER',
        'XMO_WALLET_DB_USER',
        'xmo_wallet',
      ),
      password: value(
        'XMO_EMAIL_OTP_DB_PASSWORD',
        'XMO_PASSWORD_RESET_DB_PASSWORD',
        'XMO_WALLET_DB_PASSWORD',
        '',
      ),
      codeSecret: env['XMO_EMAIL_OTP_CODE_SECRET']?.trim() ?? '',
    );
  }

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final String codeSecret;

  bool get isConfigured =>
      host.isNotEmpty &&
      database.isNotEmpty &&
      username.isNotEmpty &&
      password.isNotEmpty &&
      codeSecret.length >= 32;

  bool hasDistinctSecretFrom(Iterable<String> otherSecrets) => otherSecrets
      .map((secret) => secret.trim())
      .where((secret) => secret.isNotEmpty)
      .every((secret) => codeSecret != secret);
}

enum EmailOtpAttemptStatus {
  valid,
  notRequested,
  expired,
  tooManyAttempts,
  incorrectCode,
  alreadyProcessing,
}

class EmailOtpAttemptResult {
  const EmailOtpAttemptResult(this.status);

  final EmailOtpAttemptStatus status;
}

class EmailOtpQuotaDecision {
  const EmailOtpQuotaDecision({
    required this.allowed,
    required this.retryAfter,
  });

  final bool allowed;
  final Duration retryAfter;
}

String emailOtpSubjectDigest({
  required String secret,
  required EmailOtpPurpose purpose,
  required String subject,
}) => _hmacDigest(secret, 'xmo-email-otp-subject-v1:${purpose.value}:$subject');

String emailOtpCodeDigest({
  required String secret,
  required EmailOtpPurpose purpose,
  required String subjectDigest,
  required String code,
}) => _hmacDigest(
  secret,
  'xmo-email-otp-code-v1:${purpose.value}:$subjectDigest:$code',
);

String emailOtpQuotaDigest({
  required String secret,
  required String scope,
  required String identifier,
}) => _hmacDigest(secret, 'xmo-email-otp-quota-v1:$scope:$identifier');

String _hmacDigest(String secret, String value) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(value)).toString();

class EmailOtpChallengeStore {
  EmailOtpChallengeStore({required this.config});

  final EmailOtpChallengeStoreConfig config;

  Future<void> initialize() async {
    final connection = await _open();
    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS xmo_email_otp_challenges (
          purpose TEXT NOT NULL CHECK (
            purpose IN (
              'registration',
              'external_account_deletion',
              'password_reset'
            )
          ),
          subject_digest TEXT NOT NULL,
          code_digest TEXT NOT NULL,
          expires_at TIMESTAMPTZ NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
          claimed_until TIMESTAMPTZ,
          created_at TIMESTAMPTZ NOT NULL,
          PRIMARY KEY (purpose, subject_digest)
        )
      ''');
      await connection.execute('''
        CREATE INDEX IF NOT EXISTS xmo_email_otp_challenges_expiry_idx
        ON xmo_email_otp_challenges (expires_at)
      ''');
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS xmo_email_otp_rate_limits (
          scope TEXT NOT NULL,
          identifier_digest TEXT NOT NULL,
          window_started_at TIMESTAMPTZ NOT NULL,
          count INTEGER NOT NULL CHECK (count >= 0),
          PRIMARY KEY (scope, identifier_digest)
        )
      ''');
      await connection.execute('''
        CREATE INDEX IF NOT EXISTS xmo_email_otp_rate_limits_window_idx
        ON xmo_email_otp_rate_limits (window_started_at)
      ''');
      await _prune(connection);
    } finally {
      await connection.close();
    }
  }

  Future<void> issue({
    required EmailOtpPurpose purpose,
    required String subject,
    required String code,
    required DateTime expiresAt,
  }) async {
    final subjectDigest = _subjectDigest(purpose, subject);
    final codeDigest = _codeDigest(purpose, subjectDigest, code);
    final connection = await _open();
    try {
      await _prune(connection);
      await connection.execute(
        Sql.named('''
          INSERT INTO xmo_email_otp_challenges (
            purpose, subject_digest, code_digest, expires_at, attempts,
            claimed_until, created_at
          ) VALUES (
            @purpose, @subjectDigest, @codeDigest, @expiresAt, 0, NULL,
            @createdAt
          )
          ON CONFLICT (purpose, subject_digest) DO UPDATE SET
            code_digest = EXCLUDED.code_digest,
            expires_at = EXCLUDED.expires_at,
            attempts = 0,
            claimed_until = NULL,
            created_at = EXCLUDED.created_at
        '''),
        parameters: {
          'purpose': purpose.value,
          'subjectDigest': subjectDigest,
          'codeDigest': codeDigest,
          'expiresAt': expiresAt.toUtc(),
          'createdAt': DateTime.now().toUtc(),
        },
      );
    } finally {
      await connection.close();
    }
  }

  Future<EmailOtpAttemptResult> claimAttempt({
    required EmailOtpPurpose purpose,
    required String subject,
    required String code,
    required int maxAttempts,
    required Duration claimTtl,
  }) async {
    final subjectDigest = _subjectDigest(purpose, subject);
    final codeDigest = _codeDigest(purpose, subjectDigest, code);
    final connection = await _open();
    try {
      return await connection.runTx((transaction) async {
        final result = await transaction.execute(
          Sql.named('''
            SELECT code_digest, expires_at, attempts, claimed_until
            FROM xmo_email_otp_challenges
            WHERE purpose = @purpose AND subject_digest = @subjectDigest
            FOR UPDATE
          '''),
          parameters: {
            'purpose': purpose.value,
            'subjectDigest': subjectDigest,
          },
        );
        if (result.isEmpty) {
          return const EmailOtpAttemptResult(
            EmailOtpAttemptStatus.notRequested,
          );
        }

        final record = result.first.toColumnMap();
        final now = DateTime.now().toUtc();
        final expiresAt = (record['expires_at'] as DateTime).toUtc();
        if (!expiresAt.isAfter(now)) {
          await _removeInTransaction(transaction, purpose.value, subjectDigest);
          return const EmailOtpAttemptResult(EmailOtpAttemptStatus.expired);
        }

        final claimedUntil = record['claimed_until'] as DateTime?;
        if (claimedUntil != null && claimedUntil.toUtc().isAfter(now)) {
          return const EmailOtpAttemptResult(
            EmailOtpAttemptStatus.alreadyProcessing,
          );
        }

        final attempts = (record['attempts'] as int) + 1;
        if (attempts > maxAttempts) {
          await _removeInTransaction(transaction, purpose.value, subjectDigest);
          return const EmailOtpAttemptResult(
            EmailOtpAttemptStatus.tooManyAttempts,
          );
        }

        if (!_constantTimeEquals(record['code_digest'] as String, codeDigest)) {
          await transaction.execute(
            Sql.named('''
              UPDATE xmo_email_otp_challenges
              SET attempts = @attempts, claimed_until = NULL
              WHERE purpose = @purpose AND subject_digest = @subjectDigest
            '''),
            parameters: {
              'purpose': purpose.value,
              'subjectDigest': subjectDigest,
              'attempts': attempts,
            },
          );
          return const EmailOtpAttemptResult(
            EmailOtpAttemptStatus.incorrectCode,
          );
        }

        await transaction.execute(
          Sql.named('''
            UPDATE xmo_email_otp_challenges
            SET attempts = @attempts, claimed_until = @claimedUntil
            WHERE purpose = @purpose AND subject_digest = @subjectDigest
          '''),
          parameters: {
            'purpose': purpose.value,
            'subjectDigest': subjectDigest,
            'attempts': attempts,
            'claimedUntil': now.add(claimTtl),
          },
        );
        return const EmailOtpAttemptResult(EmailOtpAttemptStatus.valid);
      });
    } finally {
      await connection.close();
    }
  }

  Future<void> releaseClaim({
    required EmailOtpPurpose purpose,
    required String subject,
  }) async {
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          UPDATE xmo_email_otp_challenges
          SET claimed_until = NULL
          WHERE purpose = @purpose AND subject_digest = @subjectDigest
        '''),
        parameters: {
          'purpose': purpose.value,
          'subjectDigest': _subjectDigest(purpose, subject),
        },
      );
    } finally {
      await connection.close();
    }
  }

  Future<void> remove({
    required EmailOtpPurpose purpose,
    required String subject,
  }) async {
    final connection = await _open();
    try {
      await _removeInTransaction(
        connection,
        purpose.value,
        _subjectDigest(purpose, subject),
      );
    } finally {
      await connection.close();
    }
  }

  Future<EmailOtpQuotaDecision> consumeQuota({
    required EmailOtpPurpose purpose,
    required String category,
    required String identifier,
    required int limit,
    required Duration window,
  }) async {
    if (limit <= 0 || window <= Duration.zero) {
      throw ArgumentError('OTP quota limit and window must be positive');
    }
    final scope = '${purpose.value}:$category';
    final identifierDigest = emailOtpQuotaDigest(
      secret: config.codeSecret,
      scope: scope,
      identifier: identifier,
    );
    final connection = await _open();
    try {
      final now = DateTime.now().toUtc();
      final result = await connection.execute(
        Sql.named('''
          INSERT INTO xmo_email_otp_rate_limits (
            scope, identifier_digest, window_started_at, count
          ) VALUES (@scope, @identifierDigest, @now, 1)
          ON CONFLICT (scope, identifier_digest) DO UPDATE SET
            window_started_at = CASE
              WHEN xmo_email_otp_rate_limits.window_started_at <= @cutoff
                THEN @now
              ELSE xmo_email_otp_rate_limits.window_started_at
            END,
            count = CASE
              WHEN xmo_email_otp_rate_limits.window_started_at <= @cutoff
                THEN 1
              ELSE xmo_email_otp_rate_limits.count + 1
            END
          RETURNING window_started_at, count
        '''),
        parameters: {
          'scope': scope,
          'identifierDigest': identifierDigest,
          'now': now,
          'cutoff': now.subtract(window),
        },
      );
      final row = result.first.toColumnMap();
      final count = row['count'] as int;
      final startedAt = (row['window_started_at'] as DateTime).toUtc();
      final remaining = window - now.difference(startedAt);
      return EmailOtpQuotaDecision(
        allowed: count <= limit,
        retryAfter: remaining.isNegative ? Duration.zero : remaining,
      );
    } finally {
      await connection.close();
    }
  }

  String _subjectDigest(EmailOtpPurpose purpose, String subject) =>
      emailOtpSubjectDigest(
        secret: config.codeSecret,
        purpose: purpose,
        subject: subject,
      );

  String _codeDigest(
    EmailOtpPurpose purpose,
    String subjectDigest,
    String code,
  ) => emailOtpCodeDigest(
    secret: config.codeSecret,
    purpose: purpose,
    subjectDigest: subjectDigest,
    code: code,
  );

  Future<Connection> _open() {
    if (!config.isConfigured) {
      throw StateError('Email OTP database is not configured');
    }
    return Connection.open(
      Endpoint(
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        password: config.password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
  }

  Future<void> _removeInTransaction(
    Session session,
    String purpose,
    String subjectDigest,
  ) => session.execute(
    Sql.named('''
      DELETE FROM xmo_email_otp_challenges
      WHERE purpose = @purpose AND subject_digest = @subjectDigest
    '''),
    parameters: {'purpose': purpose, 'subjectDigest': subjectDigest},
  );

  Future<void> _prune(Session session) async {
    await session.execute('''
      DELETE FROM xmo_email_otp_challenges
      WHERE expires_at < NOW() - INTERVAL '1 day'
    ''');
    await session.execute('''
      DELETE FROM xmo_email_otp_rate_limits
      WHERE window_started_at < NOW() - INTERVAL '2 days'
    ''');
  }
}

bool _constantTimeEquals(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  var difference = leftBytes.length ^ rightBytes.length;
  final length = leftBytes.length < rightBytes.length
      ? leftBytes.length
      : rightBytes.length;
  for (var index = 0; index < length; index++) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference == 0;
}
