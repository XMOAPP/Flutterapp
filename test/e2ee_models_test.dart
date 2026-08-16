import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/e2ee_service.dart';

void main() {
  test('E2EE bootstrap result preserves a generated recovery key', () {
    final result = E2eeBootstrapResult.success(
      recoveryKey: 'recovery-key',
      warning: 'cleanup pending',
    );

    expect(result.success, isTrue);
    expect(result.recoveryKey, 'recovery-key');
    expect(result.error, isNull);
    expect(result.warning, 'cleanup pending');
  });

  test('E2EE bootstrap failure does not expose a recovery key', () {
    final result = E2eeBootstrapResult.failure('Sync has not completed');

    expect(result.success, isFalse);
    expect(result.recoveryKey, isNull);
    expect(result.error, 'Sync has not completed');
  });

  test('E2EE status retains independent backup and cross-signing state', () {
    const status = E2eeStatus(
      available: true,
      crossSigningEnabled: true,
      crossSigningCached: false,
      keyBackupEnabled: true,
      keyBackupCached: true,
      defaultRecoveryKeyId: 'key-id',
      deviceId: 'DEVICE',
      identityKey: 'identity',
      fingerprintKey: 'fingerprint',
      recoveryConfigured: true,
      recoveryHasPassphrase: true,
      recoverySavedConfirmed: true,
    );

    expect(status.available, isTrue);
    expect(status.crossSigningCached, isFalse);
    expect(status.keyBackupCached, isTrue);
    expect(status.recoveryConfigured, isTrue);
    expect(status.recoveryHasPassphrase, isTrue);
    expect(status.recoverySavedConfirmed, isTrue);
  });
}
