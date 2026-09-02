import 'dart:convert';

import 'package:postgres/postgres.dart';

class DonationStoreConfig {
  const DonationStoreConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  factory DonationStoreConfig.fromEnvironment(Map<String, String> env) {
    String value(String donationKey, String walletKey, String fallback) =>
        env[donationKey]?.trim().isNotEmpty == true
        ? env[donationKey]!.trim()
        : env[walletKey]?.trim().isNotEmpty == true
        ? env[walletKey]!.trim()
        : fallback;

    return DonationStoreConfig(
      host: value('XMO_DONATION_DB_HOST', 'XMO_WALLET_DB_HOST', 'postgres'),
      port:
          int.tryParse(
            value('XMO_DONATION_DB_PORT', 'XMO_WALLET_DB_PORT', '5432'),
          ) ??
          5432,
      database: value(
        'XMO_DONATION_DB_NAME',
        'XMO_WALLET_DB_NAME',
        'xmo_wallet',
      ),
      username: value(
        'XMO_DONATION_DB_USER',
        'XMO_WALLET_DB_USER',
        'xmo_wallet',
      ),
      password: value('XMO_DONATION_DB_PASSWORD', 'XMO_WALLET_DB_PASSWORD', ''),
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

class DonationStore {
  DonationStore({required this.config});

  final DonationStoreConfig config;

  Future<void> initialize() async {
    final connection = await _open();
    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS xmo_donations (
          donation_id TEXT PRIMARY KEY,
          thirdweb_payment_id TEXT NOT NULL UNIQUE,
          matrix_user_id TEXT NOT NULL,
          wallet_address TEXT NOT NULL,
          destination_chain_id INTEGER NOT NULL,
          destination_token_address TEXT NOT NULL,
          recipient_address TEXT NOT NULL,
          destination_amount NUMERIC(78, 0) NOT NULL,
          plan_json JSONB NOT NULL,
          status TEXT NOT NULL CHECK (
            status IN (
              'awaiting_signature', 'submitted', 'confirmed', 'failed',
              'expired'
            )
          ),
          created_at TIMESTAMPTZ NOT NULL,
          expires_at TIMESTAMPTZ NOT NULL,
          updated_at TIMESTAMPTZ NOT NULL
        )
      ''');
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS xmo_donation_transactions (
          donation_id TEXT NOT NULL REFERENCES xmo_donations(donation_id)
            ON DELETE CASCADE,
          transaction_id TEXT NOT NULL,
          transaction_hash TEXT NOT NULL UNIQUE,
          action TEXT NOT NULL,
          chain_id INTEGER NOT NULL,
          submitted_at TIMESTAMPTZ NOT NULL,
          PRIMARY KEY (donation_id, transaction_id)
        )
      ''');
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS xmo_thirdweb_webhook_events (
          event_digest TEXT PRIMARY KEY,
          received_at TIMESTAMPTZ NOT NULL
        )
      ''');
      await connection.execute('''
        CREATE INDEX IF NOT EXISTS xmo_donations_owner_idx
        ON xmo_donations (matrix_user_id, created_at DESC)
      ''');
      await _prune(connection);
    } finally {
      await connection.close();
    }
  }

  Future<void> create(DonationRecord record) async {
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          INSERT INTO xmo_donations (
            donation_id, thirdweb_payment_id, matrix_user_id, wallet_address,
            destination_chain_id, destination_token_address,
            recipient_address, destination_amount, plan_json, status,
            created_at, expires_at, updated_at
          ) VALUES (
            @donationId, @paymentId, @matrixUserId, @walletAddress,
            @chainId, @tokenAddress, @recipientAddress,
            CAST(@amount AS NUMERIC), CAST(@planJson AS JSONB), @status,
            @createdAt, @expiresAt, @updatedAt
          )
        '''),
        parameters: record.toParameters(),
      );
    } finally {
      await connection.close();
    }
  }

  Future<DonationRecord?> findOwned({
    required String donationId,
    required String matrixUserId,
  }) async {
    final connection = await _open();
    try {
      final result = await connection.execute(
        Sql.named('''
          SELECT donation_id, thirdweb_payment_id, matrix_user_id,
                 wallet_address, destination_chain_id,
                 destination_token_address, recipient_address,
                 destination_amount, plan_json, status, created_at,
                 expires_at, updated_at
          FROM xmo_donations
          WHERE donation_id = @donationId AND matrix_user_id = @matrixUserId
          LIMIT 1
        '''),
        parameters: {'donationId': donationId, 'matrixUserId': matrixUserId},
      );
      if (result.isEmpty) return null;
      return DonationRecord.fromColumns(result.first.toColumnMap());
    } finally {
      await connection.close();
    }
  }

  Future<DonationRecord?> findById(String donationId) async {
    final connection = await _open();
    try {
      final result = await connection.execute(
        Sql.named('''
          SELECT donation_id, thirdweb_payment_id, matrix_user_id,
                 wallet_address, destination_chain_id,
                 destination_token_address, recipient_address,
                 destination_amount, plan_json, status, created_at,
                 expires_at, updated_at
          FROM xmo_donations
          WHERE donation_id = @donationId
          LIMIT 1
        '''),
        parameters: {'donationId': donationId},
      );
      if (result.isEmpty) return null;
      return DonationRecord.fromColumns(result.first.toColumnMap());
    } finally {
      await connection.close();
    }
  }

  Future<bool> recordSubmission({
    required DonationRecord donation,
    required String transactionId,
    required String transactionHash,
    required String action,
    required int chainId,
  }) async {
    final connection = await _open();
    try {
      return await connection.runTx((transaction) async {
        final expected = donation.transactionById(transactionId);
        if (expected == null ||
            expected['action']?.toString() != action ||
            int.tryParse(expected['chainId']?.toString() ?? '') != chainId) {
          return false;
        }
        final inserted = await transaction.execute(
          Sql.named('''
            INSERT INTO xmo_donation_transactions (
              donation_id, transaction_id, transaction_hash, action,
              chain_id, submitted_at
            ) VALUES (
              @donationId, @transactionId, @transactionHash, @action,
              @chainId, @submittedAt
            )
            ON CONFLICT (donation_id, transaction_id) DO UPDATE SET
              transaction_hash = CASE
                WHEN xmo_donation_transactions.transaction_hash =
                     EXCLUDED.transaction_hash
                THEN EXCLUDED.transaction_hash
                ELSE xmo_donation_transactions.transaction_hash
              END
            RETURNING transaction_hash
          '''),
          parameters: {
            'donationId': donation.donationId,
            'transactionId': transactionId,
            'transactionHash': transactionHash,
            'action': action,
            'chainId': chainId,
            'submittedAt': DateTime.now().toUtc(),
          },
        );
        if (inserted.isEmpty ||
            inserted.first.toColumnMap()['transaction_hash']?.toString() !=
                transactionHash) {
          return false;
        }
        await transaction.execute(
          Sql.named('''
            UPDATE xmo_donations
            SET status = CASE
                  WHEN status = 'awaiting_signature' THEN 'submitted'
                  ELSE status
                END,
                updated_at = @updatedAt
            WHERE donation_id = @donationId
          '''),
          parameters: {
            'donationId': donation.donationId,
            'updatedAt': DateTime.now().toUtc(),
          },
        );
        return true;
      });
    } finally {
      await connection.close();
    }
  }

  Future<DonationTransaction?> settlementTransaction(String donationId) async {
    final connection = await _open();
    try {
      final result = await connection.execute(
        Sql.named('''
          SELECT transaction_id, transaction_hash, action, chain_id
          FROM xmo_donation_transactions
          WHERE donation_id = @donationId AND action <> 'approval'
          ORDER BY submitted_at DESC
          LIMIT 1
        '''),
        parameters: {'donationId': donationId},
      );
      if (result.isEmpty) return null;
      return DonationTransaction.fromColumns(result.first.toColumnMap());
    } finally {
      await connection.close();
    }
  }

  Future<void> updateStatus({
    required String donationId,
    required String status,
  }) async {
    const allowed = {'submitted', 'confirmed', 'failed', 'expired'};
    if (!allowed.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          UPDATE xmo_donations
          SET status = CASE
                WHEN status IN ('confirmed', 'failed', 'expired') THEN status
                ELSE @status
              END,
              updated_at = @updatedAt
          WHERE donation_id = @donationId
        '''),
        parameters: {
          'donationId': donationId,
          'status': status,
          'updatedAt': DateTime.now().toUtc(),
        },
      );
    } finally {
      await connection.close();
    }
  }

  Future<bool> claimWebhookEvent(String eventDigest) async {
    final connection = await _open();
    try {
      final result = await connection.execute(
        Sql.named('''
          INSERT INTO xmo_thirdweb_webhook_events (event_digest, received_at)
          VALUES (@eventDigest, @receivedAt)
          ON CONFLICT (event_digest) DO NOTHING
          RETURNING event_digest
        '''),
        parameters: {
          'eventDigest': eventDigest,
          'receivedAt': DateTime.now().toUtc(),
        },
      );
      return result.isNotEmpty;
    } finally {
      await connection.close();
    }
  }

  Future<void> releaseWebhookEvent(String eventDigest) async {
    final connection = await _open();
    try {
      await connection.execute(
        Sql.named('''
          DELETE FROM xmo_thirdweb_webhook_events
          WHERE event_digest = @eventDigest
        '''),
        parameters: {'eventDigest': eventDigest},
      );
    } finally {
      await connection.close();
    }
  }

  Future<Connection> _open() {
    if (!config.isConfigured) {
      throw StateError('Donation database is not configured');
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
      DELETE FROM xmo_thirdweb_webhook_events
      WHERE received_at < NOW() - INTERVAL '30 days'
    ''');
    await connection.execute('''
      UPDATE xmo_donations
      SET status = 'expired', updated_at = NOW()
      WHERE status = 'awaiting_signature' AND expires_at < NOW()
    ''');
  }
}

class DonationRecord {
  const DonationRecord({
    required this.donationId,
    required this.thirdwebPaymentId,
    required this.matrixUserId,
    required this.walletAddress,
    required this.destinationChainId,
    required this.destinationTokenAddress,
    required this.recipientAddress,
    required this.destinationAmount,
    required this.plan,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.updatedAt,
  });

  final String donationId;
  final String thirdwebPaymentId;
  final String matrixUserId;
  final String walletAddress;
  final int destinationChainId;
  final String destinationTokenAddress;
  final String recipientAddress;
  final BigInt destinationAmount;
  final Map<String, dynamic> plan;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime updatedAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, dynamic>? transactionById(String transactionId) {
    final transactions = plan['transactions'];
    if (transactions is! List) return null;
    for (final value in transactions) {
      final map = value is Map<String, dynamic>
          ? value
          : value is Map
          ? value.map((key, item) => MapEntry(key.toString(), item))
          : null;
      if (map?['id']?.toString() == transactionId) return map;
    }
    return null;
  }

  Map<String, Object?> toParameters() => {
    'donationId': donationId,
    'paymentId': thirdwebPaymentId,
    'matrixUserId': matrixUserId,
    'walletAddress': walletAddress,
    'chainId': destinationChainId,
    'tokenAddress': destinationTokenAddress,
    'recipientAddress': recipientAddress,
    'amount': destinationAmount.toString(),
    'planJson': jsonEncode(plan),
    'status': status,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'updatedAt': updatedAt,
  };

  factory DonationRecord.fromColumns(Map<String, dynamic> columns) {
    final rawPlan = columns['plan_json'];
    final decodedPlan = rawPlan is Map
        ? rawPlan.map((key, value) => MapEntry(key.toString(), value))
        : jsonDecode(rawPlan.toString()) as Map<String, dynamic>;
    return DonationRecord(
      donationId: columns['donation_id'].toString(),
      thirdwebPaymentId: columns['thirdweb_payment_id'].toString(),
      matrixUserId: columns['matrix_user_id'].toString(),
      walletAddress: columns['wallet_address'].toString(),
      destinationChainId: columns['destination_chain_id'] as int,
      destinationTokenAddress: columns['destination_token_address'].toString(),
      recipientAddress: columns['recipient_address'].toString(),
      destinationAmount: BigInt.parse(columns['destination_amount'].toString()),
      plan: decodedPlan,
      status: columns['status'].toString(),
      createdAt: columns['created_at'] as DateTime,
      expiresAt: columns['expires_at'] as DateTime,
      updatedAt: columns['updated_at'] as DateTime,
    );
  }
}

class DonationTransaction {
  const DonationTransaction({
    required this.transactionId,
    required this.transactionHash,
    required this.action,
    required this.chainId,
  });

  factory DonationTransaction.fromColumns(Map<String, dynamic> columns) =>
      DonationTransaction(
        transactionId: columns['transaction_id'].toString(),
        transactionHash: columns['transaction_hash'].toString(),
        action: columns['action'].toString(),
        chainId: columns['chain_id'] as int,
      );

  final String transactionId;
  final String transactionHash;
  final String action;
  final int chainId;
}
