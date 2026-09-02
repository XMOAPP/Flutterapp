import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:xmo_auth_server/src/email_otp_challenge_store.dart';

void main() {
  group('EmailOtpChallengeStoreConfig', () {
    test('reuses existing database settings with a dedicated OTP secret', () {
      final config = EmailOtpChallengeStoreConfig.fromEnvironment({
        'XMO_WALLET_DB_HOST': 'postgres',
        'XMO_WALLET_DB_NAME': 'xmo_wallet',
        'XMO_WALLET_DB_USER': 'xmo_wallet',
        'XMO_WALLET_DB_PASSWORD': 'database-password',
        'XMO_EMAIL_OTP_CODE_SECRET': 'o' * 32,
      });

      expect(config.database, 'xmo_wallet');
      expect(config.username, 'xmo_wallet');
      expect(config.isConfigured, isTrue);
      expect(config.hasDistinctSecretFrom(['w' * 32, 'r' * 32]), isTrue);
      expect(config.hasDistinctSecretFrom(['o' * 32]), isFalse);
    });

    test('does not reuse the wallet JWT or password-reset secret', () {
      final config = EmailOtpChallengeStoreConfig.fromEnvironment({
        'XMO_WALLET_DB_PASSWORD': 'database-password',
        'XMO_WALLET_JWT_SECRET': 'w' * 32,
        'XMO_PASSWORD_RESET_CODE_SECRET': 'r' * 32,
      });

      expect(config.codeSecret, isEmpty);
      expect(config.isConfigured, isFalse);
    });
  });

  test('digests hide subjects and separate codes by purpose', () {
    final registrationSubject = emailOtpSubjectDigest(
      secret: 's' * 32,
      purpose: EmailOtpPurpose.registration,
      subject: 'person@example.com',
    );
    final deletionSubject = emailOtpSubjectDigest(
      secret: 's' * 32,
      purpose: EmailOtpPurpose.externalAccountDeletion,
      subject: 'person@example.com',
    );
    final registrationCode = emailOtpCodeDigest(
      secret: 's' * 32,
      purpose: EmailOtpPurpose.registration,
      subjectDigest: registrationSubject,
      code: '123456',
    );
    final deletionCode = emailOtpCodeDigest(
      secret: 's' * 32,
      purpose: EmailOtpPurpose.externalAccountDeletion,
      subjectDigest: deletionSubject,
      code: '123456',
    );

    expect(registrationSubject, isNot(contains('person@example.com')));
    expect(registrationSubject, isNot(deletionSubject));
    expect(registrationCode, isNot('123456'));
    expect(registrationCode, isNot(deletionCode));
  });

  final runPostgresTests =
      Platform.environment['XMO_TEST_POSTGRES']?.toLowerCase() == 'true';
  final integrationConfig = EmailOtpChallengeStoreConfig.fromEnvironment(
    Platform.environment,
  );

  group(
    'EmailOtpChallengeStore PostgreSQL',
    () {
      late EmailOtpChallengeStore store;

      setUp(() async {
        store = EmailOtpChallengeStore(config: integrationConfig);
        await store.initialize();
      });

      String uniqueSubject(String label) =>
          '$label-${DateTime.now().microsecondsSinceEpoch}@example.test';

      test('survives restart and consumes a valid code once', () async {
        final subject = uniqueSubject('restart');
        await store.issue(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );

        final restartedStore = EmailOtpChallengeStore(
          config: integrationConfig,
        );
        final first = await restartedStore.claimAttempt(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          maxAttempts: 5,
          claimTtl: const Duration(minutes: 2),
        );
        await restartedStore.remove(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
        );
        final replay = await store.claimAttempt(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          maxAttempts: 5,
          claimTtl: const Duration(minutes: 2),
        );

        expect(first.status, EmailOtpAttemptStatus.valid);
        expect(replay.status, EmailOtpAttemptStatus.notRequested);
      });

      test('persists neither the raw subject nor the raw code', () async {
        final subject = uniqueSubject('storage');
        await store.issue(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );

        final connection = await Connection.open(
          Endpoint(
            host: integrationConfig.host,
            port: integrationConfig.port,
            database: integrationConfig.database,
            username: integrationConfig.username,
            password: integrationConfig.password,
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        try {
          final rows = await connection.execute(
            Sql.named('''
              SELECT subject_digest, code_digest
              FROM xmo_email_otp_challenges
              WHERE purpose = @purpose
              ORDER BY created_at DESC
              LIMIT 1
            '''),
            parameters: {'purpose': EmailOtpPurpose.registration.value},
          );
          final stored = rows.first.toColumnMap();
          expect(stored['subject_digest'], isNot(subject));
          expect(stored['subject_digest'].toString(), isNot(contains(subject)));
          expect(stored['code_digest'], isNot('123456'));
          expect(stored['code_digest'].toString(), isNot(contains('123456')));
        } finally {
          await connection.close();
        }
      });

      test('resend invalidates the previous code', () async {
        final subject = uniqueSubject('resend');
        final expiresAt = DateTime.now().toUtc().add(
          const Duration(minutes: 5),
        );
        await store.issue(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '111111',
          expiresAt: expiresAt,
        );
        await store.issue(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '222222',
          expiresAt: expiresAt,
        );

        final oldCode = await store.claimAttempt(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '111111',
          maxAttempts: 5,
          claimTtl: const Duration(minutes: 2),
        );
        final newCode = await store.claimAttempt(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '222222',
          maxAttempts: 5,
          claimTtl: const Duration(minutes: 2),
        );

        expect(oldCode.status, EmailOtpAttemptStatus.incorrectCode);
        expect(newCode.status, EmailOtpAttemptStatus.valid);
      });

      test('purpose separation prevents cross-flow verification', () async {
        final subject = uniqueSubject('purpose');
        await store.issue(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );

        final result = await store.claimAttempt(
          purpose: EmailOtpPurpose.externalAccountDeletion,
          subject: subject,
          code: '123456',
          maxAttempts: 5,
          claimTtl: const Duration(minutes: 2),
        );

        expect(result.status, EmailOtpAttemptStatus.notRequested);
      });

      test('accepts only one concurrent verification', () async {
        final subject = uniqueSubject('concurrent');
        await store.issue(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );

        final results = await Future.wait([
          store.claimAttempt(
            purpose: EmailOtpPurpose.registration,
            subject: subject,
            code: '123456',
            maxAttempts: 5,
            claimTtl: const Duration(minutes: 2),
          ),
          EmailOtpChallengeStore(config: integrationConfig).claimAttempt(
            purpose: EmailOtpPurpose.registration,
            subject: subject,
            code: '123456',
            maxAttempts: 5,
            claimTtl: const Duration(minutes: 2),
          ),
        ]);

        expect(
          results.map((result) => result.status),
          containsAll([
            EmailOtpAttemptStatus.valid,
            EmailOtpAttemptStatus.alreadyProcessing,
          ]),
        );
      });

      test('removes an expired challenge', () async {
        final subject = uniqueSubject('expired');
        await store.issue(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          expiresAt: DateTime.now().toUtc().subtract(
            const Duration(seconds: 1),
          ),
        );

        final expired = await store.claimAttempt(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          maxAttempts: 5,
          claimTtl: const Duration(minutes: 2),
        );
        final removed = await store.claimAttempt(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          maxAttempts: 5,
          claimTtl: const Duration(minutes: 2),
        );

        expect(expired.status, EmailOtpAttemptStatus.expired);
        expect(removed.status, EmailOtpAttemptStatus.notRequested);
      });

      test('removes a challenge after the attempt limit', () async {
        final subject = uniqueSubject('attempts');
        await store.issue(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );

        for (var attempt = 0; attempt < 2; attempt++) {
          final result = await store.claimAttempt(
            purpose: EmailOtpPurpose.registration,
            subject: subject,
            code: '000000',
            maxAttempts: 2,
            claimTtl: const Duration(minutes: 2),
          );
          expect(result.status, EmailOtpAttemptStatus.incorrectCode);
        }
        final limited = await store.claimAttempt(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '000000',
          maxAttempts: 2,
          claimTtl: const Duration(minutes: 2),
        );
        final removed = await store.claimAttempt(
          purpose: EmailOtpPurpose.registration,
          subject: subject,
          code: '123456',
          maxAttempts: 2,
          claimTtl: const Duration(minutes: 2),
        );

        expect(limited.status, EmailOtpAttemptStatus.tooManyAttempts);
        expect(removed.status, EmailOtpAttemptStatus.notRequested);
      });

      test('persists rate limits across store instances', () async {
        final identifier = uniqueSubject('quota');
        for (var attempt = 0; attempt < 2; attempt++) {
          final decision = await store.consumeQuota(
            purpose: EmailOtpPurpose.registration,
            category: 'test-target',
            identifier: identifier,
            limit: 2,
            window: const Duration(hours: 1),
          );
          expect(decision.allowed, isTrue);
        }

        final restartedStore = EmailOtpChallengeStore(
          config: integrationConfig,
        );
        final limited = await restartedStore.consumeQuota(
          purpose: EmailOtpPurpose.registration,
          category: 'test-target',
          identifier: identifier,
          limit: 2,
          window: const Duration(hours: 1),
        );

        expect(limited.allowed, isFalse);
        expect(limited.retryAfter, greaterThan(Duration.zero));
      });
    },
    skip: runPostgresTests ? false : 'PostgreSQL integration is not enabled',
  );
}
