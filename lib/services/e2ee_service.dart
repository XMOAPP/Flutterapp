import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'matrix_service.dart';

class E2eeStatus {
  final bool available;
  final bool crossSigningEnabled;
  final bool crossSigningCached;
  final bool keyBackupEnabled;
  final bool keyBackupCached;
  final String? defaultRecoveryKeyId;
  final String? deviceId;
  final String identityKey;
  final String fingerprintKey;

  const E2eeStatus({
    required this.available,
    required this.crossSigningEnabled,
    required this.crossSigningCached,
    required this.keyBackupEnabled,
    required this.keyBackupCached,
    required this.defaultRecoveryKeyId,
    required this.deviceId,
    required this.identityKey,
    required this.fingerprintKey,
  });
}

class E2eeBootstrapResult {
  final bool success;
  final String? recoveryKey;
  final String? error;

  const E2eeBootstrapResult._({
    required this.success,
    this.recoveryKey,
    this.error,
  });

  factory E2eeBootstrapResult.success({String? recoveryKey}) {
    return E2eeBootstrapResult._(
      success: true,
      recoveryKey: recoveryKey,
    );
  }

  factory E2eeBootstrapResult.failure(String error) {
    return E2eeBootstrapResult._(
      success: false,
      error: error,
    );
  }
}

class E2eeService {
  final MatrixService _matrixService;

  E2eeService(this._matrixService);

  Client get _client => _matrixService.client;

  Encryption? get _encryption => _client.encryption;

  Future<E2eeStatus> getStatus() async {
    final encryption = _encryption;
    if (encryption == null || !encryption.enabled) {
      return E2eeStatus(
        available: false,
        crossSigningEnabled: false,
        crossSigningCached: false,
        keyBackupEnabled: false,
        keyBackupCached: false,
        defaultRecoveryKeyId: null,
        deviceId: _client.deviceID,
        identityKey: _client.identityKey,
        fingerprintKey: _client.fingerprintKey,
      );
    }

    bool crossSigningCached = false;
    bool keyBackupCached = false;
    try {
      crossSigningCached = await encryption.crossSigning.isCached();
    } catch (_) {
      crossSigningCached = false;
    }
    try {
      keyBackupCached = await encryption.keyManager.isCached();
    } catch (_) {
      keyBackupCached = false;
    }

    return E2eeStatus(
      available: true,
      crossSigningEnabled: encryption.crossSigning.enabled,
      crossSigningCached: crossSigningCached,
      keyBackupEnabled: encryption.keyManager.enabled,
      keyBackupCached: keyBackupCached,
      defaultRecoveryKeyId: encryption.ssss.defaultKeyId,
      deviceId: _client.deviceID,
      identityKey: _client.identityKey,
      fingerprintKey: _client.fingerprintKey,
    );
  }

  Future<E2eeBootstrapResult> setupRecoveryAndKeyBackup({
    String? passphrase,
  }) async {
    final encryption = _encryption;
    if (encryption == null || !encryption.enabled) {
      return E2eeBootstrapResult.failure(
        'Encryption is not available on this session.',
      );
    }

    await _prepareBootstrapSyncState();

    final bootstrap = encryption.bootstrap();
    SdkError? lastEncryptionError;
    final errorSubscription = _client.onEncryptionError.stream.listen((error) {
      lastEncryptionError = error;
    });
    try {
      for (var step = 0; step < 60; step++) {
        switch (bootstrap.state) {
          case BootstrapState.loading:
            await Future<void>.delayed(const Duration(milliseconds: 150));
            continue;
          case BootstrapState.askWipeSsss:
            bootstrap.wipeSsss(false);
            continue;
          case BootstrapState.askUseExistingSsss:
            bootstrap.useExistingSsss(true);
            continue;
          case BootstrapState.askBadSsss:
            bootstrap.ignoreBadSecrets(true);
            continue;
          case BootstrapState.askUnlockSsss:
            return E2eeBootstrapResult.failure(
              'Existing recovery needs to be unlocked first.',
            );
          case BootstrapState.askNewSsss:
            await bootstrap.newSsss(
                passphrase?.trim().isEmpty == true ? null : passphrase?.trim());
            continue;
          case BootstrapState.openExistingSsss:
            if (bootstrap.newSsssKey?.isUnlocked != true) {
              return E2eeBootstrapResult.failure(
                'Existing recovery needs to be unlocked first.',
              );
            }
            await bootstrap.openExistingSsss();
            continue;
          case BootstrapState.askWipeCrossSigning:
            await bootstrap.wipeCrossSigning(false);
            continue;
          case BootstrapState.askSetupCrossSigning:
            await bootstrap.askSetupCrossSigning(
              setupMasterKey: true,
              setupSelfSigningKey: true,
              setupUserSigningKey: true,
            );
            continue;
          case BootstrapState.askWipeOnlineKeyBackup:
            bootstrap.wipeOnlineKeyBackup(false);
            continue;
          case BootstrapState.askSetupOnlineKeyBackup:
            await bootstrap.askSetupOnlineKeyBackup(true);
            continue;
          case BootstrapState.done:
            return E2eeBootstrapResult.success(
              recoveryKey: bootstrap.newSsssKey?.recoveryKey,
            );
          case BootstrapState.error:
            return E2eeBootstrapResult.failure(
              _formatBootstrapError(lastEncryptionError),
            );
        }
      }
    } catch (e, s) {
      debugPrint('[E2EE] Recovery setup failed: $e\n$s');
      return E2eeBootstrapResult.failure(_formatException(e));
    } finally {
      await errorSubscription.cancel();
    }

    return E2eeBootstrapResult.failure(
      'Recovery setup did not finish. Try again after syncing finishes.',
    );
  }

  Future<E2eeBootstrapResult> unlockRecoveryAndLoadKeys(
    String keyOrPassphrase,
  ) async {
    final encryption = _encryption;
    if (encryption == null || !encryption.enabled) {
      return E2eeBootstrapResult.failure(
        'Encryption is not available on this session.',
      );
    }

    try {
      final recovery = encryption.ssss.open();
      await recovery.unlock(keyOrPassphrase: keyOrPassphrase.trim());
      await recovery.maybeCacheAll();
      if (encryption.keyManager.enabled) {
        await encryption.keyManager.loadAllKeys();
      }
      return E2eeBootstrapResult.success(recoveryKey: recovery.recoveryKey);
    } catch (e, s) {
      debugPrint('[E2EE] Recovery unlock failed: $e\n$s');
      return E2eeBootstrapResult.failure(
        'Recovery key or passphrase is invalid.',
      );
    }
  }

  Future<void> requestSecretsFromVerifiedDevices() async {
    final encryption = _encryption;
    if (encryption == null || !encryption.enabled) return;
    await encryption.ssss.maybeRequestAll();
  }

  Future<void> _prepareBootstrapSyncState() async {
    try {
      await _client.oneShotSync();
    } catch (e, s) {
      debugPrint('[E2EE] Pre-bootstrap sync failed: $e\n$s');
    }
    try {
      await _client.updateUserDeviceKeys(additionalUsers: {_client.userID!});
    } catch (e, s) {
      debugPrint('[E2EE] Pre-bootstrap device-key update failed: $e\n$s');
    }
  }

  String _formatBootstrapError(SdkError? error) {
    if (error?.exception != null) {
      return _formatException(error!.exception);
    }
    return 'Recovery setup failed while creating cross-signing or key backup. Try again after syncing finishes.';
  }

  String _formatException(Object? exception) {
    if (exception is MatrixException) {
      return '${exception.errcode}: ${exception.errorMessage}';
    }
    final message = exception?.toString().trim();
    if (message == null || message.isEmpty) {
      return 'Recovery setup failed. Try again after syncing finishes.';
    }
    return message;
  }
}
