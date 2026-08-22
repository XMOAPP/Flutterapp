import 'package:postgres/postgres.dart';

class WalletAccountStoreConfig {
  const WalletAccountStoreConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  factory WalletAccountStoreConfig.fromEnvironment(Map<String, String> env) {
    return WalletAccountStoreConfig(
      host: env['XMO_WALLET_DB_HOST']?.trim() ?? 'postgres',
      port: int.tryParse(env['XMO_WALLET_DB_PORT'] ?? '') ?? 5432,
      database: env['XMO_WALLET_DB_NAME']?.trim() ?? 'xmo_wallet',
      username: env['XMO_WALLET_DB_USER']?.trim() ?? 'xmo_wallet',
      password: env['XMO_WALLET_DB_PASSWORD'] ?? '',
    );
  }

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  bool get isConfigured =>
      host.isNotEmpty &&
      database.isNotEmpty &&
      username.isNotEmpty &&
      password.isNotEmpty;
}

class WalletAccountStore {
  WalletAccountStore({required this.config});

  final WalletAccountStoreConfig config;

  Future<void> initialize() async {
    final connection = await _open();
    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS xmo_wallet_accounts (
          wallet_type TEXT NOT NULL,
          wallet_address TEXT NOT NULL,
          username TEXT NOT NULL UNIQUE,
          matrix_user_id TEXT NOT NULL UNIQUE,
          chain_id TEXT NOT NULL,
          status TEXT NOT NULL CHECK (status IN ('pending', 'active')),
          created_at TIMESTAMPTZ NOT NULL,
          updated_at TIMESTAMPTZ NOT NULL,
          PRIMARY KEY (wallet_type, wallet_address)
        )
      ''');
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS xmo_wallet_challenges (
          nonce TEXT PRIMARY KEY,
          username TEXT NOT NULL,
          wallet_type TEXT NOT NULL,
          wallet_address TEXT NOT NULL,
          chain_id TEXT NOT NULL,
          mode TEXT NOT NULL CHECK (mode IN ('create', 'login')),
          message TEXT NOT NULL,
          expires_at TIMESTAMPTZ NOT NULL,
          consumed_at TIMESTAMPTZ
        )
      ''');
      await connection.execute('''
        CREATE INDEX IF NOT EXISTS xmo_wallet_challenges_expiry_idx
        ON xmo_wallet_challenges (expires_at)
      ''');
      await _prune(connection);
    } finally {
      await connection.close();
    }
  }

  Future<WalletAccount?> findAccount({
    required String walletType,
    required String walletAddress,
    bool includePending = false,
  }) async {
    final connection = await _open();
    try {
      final result = await connection.execute(
        Sql.named('''
          SELECT wallet_type, wallet_address, username, matrix_user_id,
                 chain_id, status, created_at
          FROM xmo_wallet_accounts
          WHERE wallet_type = @walletType
            AND wallet_address = @walletAddress
            ${includePending ? '' : "AND status = 'active'"}
          LIMIT 1
        '''),
        parameters: {
          'walletType': walletType,
          'walletAddress': walletAddress,
        },
      );
      if (result.isEmpty) return null;
      return WalletAccount.fromColumns(result.first.toColumnMap());
    } finally {
      await connection.close();
    }
  }

  Future<bool> usernameExists(String username) async {
    final connection = await _open();
    try {
      final result = await connection.execute(
        Sql.named('''
          SELECT 1 FROM xmo_wallet_accounts WHERE username = @username LIMIT 1
        '''),
        parameters: {'username': username},
      );
      return result.isNotEmpty;
    } finally {
      await connection.close();
    }
  }

  /// Finds the active wallet-only account associated with a Matrix session.
  /// The caller must first validate the session token with Synapse.
  Future<WalletAccount?> findActiveAccountByMatrixUserId(
    String matrixUserId,
  ) async {
    final connection = await _open();
    try {
      final result = await connection.execute(
        Sql.named('''
          SELECT wallet_type, wallet_address, username, matrix_user_id,
                 chain_id, status, created_at
          FROM xmo_wallet_accounts
          WHERE matrix_user_id = @matrixUserId
            AND status = 'active'
          LIMIT 1
        '''),
        parameters: {'matrixUserId': matrixUserId},
      );
      if (result.isEmpty) return null;
      return WalletAccount.fromColumns(result.first.toColumnMap());
    } finally {
      await connection.close();
    }
  }

  Future<void> saveChallenge(WalletStoredChallenge challenge) async {
    final connection = await _open();
    try {
      await _prune(connection);
      await connection.execute(
        Sql.named('''
          INSERT INTO xmo_wallet_challenges (
            nonce, username, wallet_type, wallet_address, chain_id, mode,
            message, expires_at
          ) VALUES (
            @nonce, @username, @walletType, @walletAddress, @chainId, @mode,
            @message, @expiresAt
          )
        '''),
        parameters: challenge.toParameters(),
      );
    } finally {
      await connection.close();
    }
  }

  Future<WalletStoredChallenge?> consumeChallenge(String nonce) async {
    final connection = await _open();
    try {
      return await connection.runTx((transaction) async {
        final result = await transaction.execute(
          Sql.named('''
            SELECT nonce, username, wallet_type, wallet_address, chain_id,
                   mode, message, expires_at, consumed_at
            FROM xmo_wallet_challenges
            WHERE nonce = @nonce
            FOR UPDATE
          '''),
          parameters: {'nonce': nonce},
        );
        if (result.isEmpty) return null;
        final challenge = WalletStoredChallenge.fromColumns(
          result.first.toColumnMap(),
        );
        final now = DateTime.now().toUtc();
        if (challenge.consumedAt != null || !challenge.expiresAt.isAfter(now)) {
          return null;
        }
        await transaction.execute(
          Sql.named('''
            UPDATE xmo_wallet_challenges
            SET consumed_at = @consumedAt
            WHERE nonce = @nonce
          '''),
          parameters: {'nonce': nonce, 'consumedAt': now},
        );
        return challenge;
      });
    } finally {
      await connection.close();
    }
  }

  Future<void> reserveAccount(WalletAccount account) async {
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          INSERT INTO xmo_wallet_accounts (
            wallet_type, wallet_address, username, matrix_user_id, chain_id,
            status, created_at, updated_at
          ) VALUES (
            @walletType, @walletAddress, @username, @matrixUserId, @chainId,
            'pending', @createdAt, @createdAt
          )
        '''),
        parameters: account.toParameters(),
      );
    } catch (_) {
      throw const WalletAccountConflict();
    } finally {
      await connection.close();
    }
  }

  Future<void> activateAccount({
    required String walletType,
    required String walletAddress,
  }) async {
    final connection = await _open();
    try {
      final result = await connection.execute(
        Sql.named('''
          UPDATE xmo_wallet_accounts
          SET status = 'active', updated_at = @updatedAt
          WHERE wallet_type = @walletType
            AND wallet_address = @walletAddress
            AND status = 'pending'
        '''),
        parameters: {
          'walletType': walletType,
          'walletAddress': walletAddress,
          'updatedAt': DateTime.now().toUtc(),
        },
      );
      if (result.affectedRows != 1) {
        throw StateError('Wallet account reservation was not found');
      }
    } finally {
      await connection.close();
    }
  }

  Future<void> removePendingAccount({
    required String walletType,
    required String walletAddress,
  }) async {
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          DELETE FROM xmo_wallet_accounts
          WHERE wallet_type = @walletType
            AND wallet_address = @walletAddress
            AND status = 'pending'
        '''),
        parameters: {
          'walletType': walletType,
          'walletAddress': walletAddress,
        },
      );
    } finally {
      await connection.close();
    }
  }

  Future<void> removeUsername(String username) async {
    final connection = await _open();
    try {
      await connection.runTx((transaction) async {
        await transaction.execute(
          Sql.named(
              'DELETE FROM xmo_wallet_challenges WHERE username = @username'),
          parameters: {'username': username},
        );
        await transaction.execute(
          Sql.named(
              'DELETE FROM xmo_wallet_accounts WHERE username = @username'),
          parameters: {'username': username},
        );
      });
    } finally {
      await connection.close();
    }
  }

  Future<Connection> _open() {
    if (!config.isConfigured) {
      throw StateError('Wallet account database is not configured');
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

  Future<void> _prune(Session connection) async {
    await connection.execute('''
      DELETE FROM xmo_wallet_challenges
      WHERE expires_at < NOW() - INTERVAL '1 day'
    ''');
  }
}

class WalletAccount {
  const WalletAccount({
    required this.walletType,
    required this.walletAddress,
    required this.username,
    required this.matrixUserId,
    required this.chainId,
    required this.status,
    required this.createdAt,
  });

  final String walletType;
  final String walletAddress;
  final String username;
  final String matrixUserId;
  final String chainId;
  final String status;
  final DateTime createdAt;

  bool get isActive => status == 'active';

  Map<String, Object?> toParameters() => {
        'walletType': walletType,
        'walletAddress': walletAddress,
        'username': username,
        'matrixUserId': matrixUserId,
        'chainId': chainId,
        'createdAt': createdAt,
      };

  factory WalletAccount.fromColumns(Map<String, dynamic> columns) {
    return WalletAccount(
      walletType: columns['wallet_type']?.toString() ?? '',
      walletAddress: columns['wallet_address']?.toString() ?? '',
      username: columns['username']?.toString() ?? '',
      matrixUserId: columns['matrix_user_id']?.toString() ?? '',
      chainId: columns['chain_id']?.toString() ?? '',
      status: columns['status']?.toString() ?? '',
      createdAt: columns['created_at'] as DateTime,
    );
  }
}

class WalletStoredChallenge {
  const WalletStoredChallenge({
    required this.nonce,
    required this.username,
    required this.walletType,
    required this.walletAddress,
    required this.chainId,
    required this.mode,
    required this.message,
    required this.expiresAt,
    this.consumedAt,
  });

  final String nonce;
  final String username;
  final String walletType;
  final String walletAddress;
  final String chainId;
  final String mode;
  final String message;
  final DateTime expiresAt;
  final DateTime? consumedAt;

  Map<String, Object?> toParameters() => {
        'nonce': nonce,
        'username': username,
        'walletType': walletType,
        'walletAddress': walletAddress,
        'chainId': chainId,
        'mode': mode,
        'message': message,
        'expiresAt': expiresAt,
      };

  factory WalletStoredChallenge.fromColumns(Map<String, dynamic> columns) {
    return WalletStoredChallenge(
      nonce: columns['nonce']?.toString() ?? '',
      username: columns['username']?.toString() ?? '',
      walletType: columns['wallet_type']?.toString() ?? '',
      walletAddress: columns['wallet_address']?.toString() ?? '',
      chainId: columns['chain_id']?.toString() ?? '',
      mode: columns['mode']?.toString() ?? '',
      message: columns['message']?.toString() ?? '',
      expiresAt: columns['expires_at'] as DateTime,
      consumedAt: columns['consumed_at'] as DateTime?,
    );
  }
}

class WalletAccountConflict implements Exception {
  const WalletAccountConflict();
}
