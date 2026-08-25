import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

class PasswordResetStoreConfig {
  const PasswordResetStoreConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.codeSecret,
  });

  factory PasswordResetStoreConfig.fromEnvironment(Map<String, String> env) {
    String value(String resetName, String walletName, String fallback) {
      final resetValue = env[resetName]?.trim();
      if (resetValue != null && resetValue.isNotEmpty) return resetValue;
      final walletValue = env[walletName]?.trim();
      if (walletValue != null && walletValue.isNotEmpty) return walletValue;
      return fallback;
    }

    return PasswordResetStoreConfig(
      host: value(
        'XMO_PASSWORD_RESET_DB_HOST',
        'XMO_WALLET_DB_HOST',
        'postgres',
      ),
      port:
          int.tryParse(
            value('XMO_PASSWORD_RESET_DB_PORT', 'XMO_WALLET_DB_PORT', '5432'),
          ) ??
          5432,
      database: value(
        'XMO_PASSWORD_RESET_DB_NAME',
        'XMO_WALLET_DB_NAME',
        'xmo_wallet',
      ),
      username: value(
        'XMO_PASSWORD_RESET_DB_USER',
        'XMO_WALLET_DB_USER',
        'xmo_wallet',
      ),
      password: value(
        'XMO_PASSWORD_RESET_DB_PASSWORD',
        'XMO_WALLET_DB_PASSWORD',
        '',
      ),
      codeSecret: value(
        'XMO_PASSWORD_RESET_CODE_SECRET',
        'XMO_WALLET_JWT_SECRET',
        '',
      ),
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
}

/// Hashes a reset code before it reaches persistent storage.
///
/// The action prefix domain-separates this HMAC from other uses of the same
/// deployment secret while an installation migrates to a dedicated reset key.
String passwordResetCodeDigest({required String code, required String secret}) {
  return Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode('xmo-password-reset-v1:$code')).toString();
}

enum PasswordResetAttemptStatus {
  valid,
  notRequested,
  expired,
  tooManyAttempts,
  incorrectCode,
  alreadyProcessing,
}

class PasswordResetAttemptResult {
  const PasswordResetAttemptResult(this.status);

  final PasswordResetAttemptStatus status;
}

class PasswordResetStore {
  PasswordResetStore({required this.config});

  final PasswordResetStoreConfig config;

  Future<void> initialize() async {
    final connection = await _open();
    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS xmo_password_reset_challenges (
          username TEXT NOT NULL,
          email TEXT NOT NULL,
          code_digest TEXT NOT NULL,
          expires_at TIMESTAMPTZ NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
          claimed_until TIMESTAMPTZ,
          created_at TIMESTAMPTZ NOT NULL,
          PRIMARY KEY (username, email)
        )
      ''');
      await connection.execute('''
        CREATE INDEX IF NOT EXISTS xmo_password_reset_challenges_expiry_idx
        ON xmo_password_reset_challenges (expires_at)
      ''');
      await _prune(connection);
    } finally {
      await connection.close();
    }
  }

  Future<void> issue({
    required String username,
    required String email,
    required String codeDigest,
    required DateTime expiresAt,
  }) async {
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          INSERT INTO xmo_password_reset_challenges (
            username, email, code_digest, expires_at, attempts, claimed_until,
            created_at
          ) VALUES (
            @username, @email, @codeDigest, @expiresAt, 0, NULL, @createdAt
          )
          ON CONFLICT (username, email) DO UPDATE SET
            code_digest = EXCLUDED.code_digest,
            expires_at = EXCLUDED.expires_at,
            attempts = 0,
            claimed_until = NULL,
            created_at = EXCLUDED.created_at
        '''),
        parameters: {
          'username': username,
          'email': email,
          'codeDigest': codeDigest,
          'expiresAt': expiresAt.toUtc(),
          'createdAt': DateTime.now().toUtc(),
        },
      );
    } finally {
      await connection.close();
    }
  }

  Future<PasswordResetAttemptResult> claimAttempt({
    required String username,
    required String email,
    required String codeDigest,
    required int maxAttempts,
    required Duration claimTtl,
  }) async {
    final connection = await _open();
    try {
      return await connection.runTx((transaction) async {
        final result = await transaction.execute(
          Sql.named('''
            SELECT code_digest, expires_at, attempts, claimed_until
            FROM xmo_password_reset_challenges
            WHERE username = @username AND email = @email
            FOR UPDATE
          '''),
          parameters: {'username': username, 'email': email},
        );
        if (result.isEmpty) {
          return const PasswordResetAttemptResult(
            PasswordResetAttemptStatus.notRequested,
          );
        }

        final record = result.first.toColumnMap();
        final now = DateTime.now().toUtc();
        final expiresAt = record['expires_at'] as DateTime;
        if (!expiresAt.isAfter(now)) {
          await _removeInTransaction(transaction, username, email);
          return const PasswordResetAttemptResult(
            PasswordResetAttemptStatus.expired,
          );
        }

        final claimedUntil = record['claimed_until'] as DateTime?;
        if (claimedUntil != null && claimedUntil.isAfter(now)) {
          return const PasswordResetAttemptResult(
            PasswordResetAttemptStatus.alreadyProcessing,
          );
        }

        final attempts = (record['attempts'] as int) + 1;
        if (attempts > maxAttempts) {
          await _removeInTransaction(transaction, username, email);
          return const PasswordResetAttemptResult(
            PasswordResetAttemptStatus.tooManyAttempts,
          );
        }

        if (!_constantTimeEquals(record['code_digest'] as String, codeDigest)) {
          await transaction.execute(
            Sql.named('''
              UPDATE xmo_password_reset_challenges
              SET attempts = @attempts, claimed_until = NULL
              WHERE username = @username AND email = @email
            '''),
            parameters: {
              'username': username,
              'email': email,
              'attempts': attempts,
            },
          );
          return const PasswordResetAttemptResult(
            PasswordResetAttemptStatus.incorrectCode,
          );
        }

        await transaction.execute(
          Sql.named('''
            UPDATE xmo_password_reset_challenges
            SET attempts = @attempts, claimed_until = @claimedUntil
            WHERE username = @username AND email = @email
          '''),
          parameters: {
            'username': username,
            'email': email,
            'attempts': attempts,
            'claimedUntil': now.add(claimTtl),
          },
        );
        return const PasswordResetAttemptResult(
          PasswordResetAttemptStatus.valid,
        );
      });
    } finally {
      await connection.close();
    }
  }

  Future<void> releaseClaim({
    required String username,
    required String email,
  }) async {
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          UPDATE xmo_password_reset_challenges
          SET claimed_until = NULL
          WHERE username = @username AND email = @email
        '''),
        parameters: {'username': username, 'email': email},
      );
    } finally {
      await connection.close();
    }
  }

  Future<void> remove({required String username, required String email}) async {
    final connection = await _open();
    try {
      await _removeInTransaction(connection, username, email);
    } finally {
      await connection.close();
    }
  }

  Future<void> removeForUsername(String username) async {
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          DELETE FROM xmo_password_reset_challenges
          WHERE username = @username
        '''),
        parameters: {'username': username},
      );
    } finally {
      await connection.close();
    }
  }

  Future<Connection> _open() {
    if (!config.isConfigured) {
      throw StateError('Password reset database is not configured');
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
    String username,
    String email,
  ) {
    return session.execute(
      Sql.named('''
        DELETE FROM xmo_password_reset_challenges
        WHERE username = @username AND email = @email
      '''),
      parameters: {'username': username, 'email': email},
    );
  }

  Future<void> _prune(Session connection) {
    return connection.execute('''
      DELETE FROM xmo_password_reset_challenges
      WHERE expires_at < NOW() - INTERVAL '1 day'
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
