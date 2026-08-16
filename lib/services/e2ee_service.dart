import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../utils/user_facing_error.dart';
import 'matrix_service.dart';
import 'recovery_key_acknowledgement_store.dart';

class E2eeStatus {
  final bool available;
  final bool vodozemacEngineActive;
  final bool crossSigningEnabled;
  final bool crossSigningCached;
  final bool keyBackupEnabled;
  final bool keyBackupCached;
  final String? defaultRecoveryKeyId;
  final String? deviceId;
  final String identityKey;
  final String fingerprintKey;
  final bool recoveryConfigured;
  final bool recoveryHasPassphrase;
  final bool recoverySavedConfirmed;

  const E2eeStatus({
    required this.available,
    this.vodozemacEngineActive = false,
    required this.crossSigningEnabled,
    required this.crossSigningCached,
    required this.keyBackupEnabled,
    required this.keyBackupCached,
    required this.defaultRecoveryKeyId,
    required this.deviceId,
    required this.identityKey,
    required this.fingerprintKey,
    this.recoveryConfigured = false,
    this.recoveryHasPassphrase = false,
    this.recoverySavedConfirmed = false,
  });
}

class E2eeBootstrapResult {
  final bool success;
  final String? recoveryKey;
  final String? error;
  final String? warning;

  const E2eeBootstrapResult._({
    required this.success,
    this.recoveryKey,
    this.error,
    this.warning,
  });

  factory E2eeBootstrapResult.success({String? recoveryKey, String? warning}) {
    return E2eeBootstrapResult._(
      success: true,
      recoveryKey: recoveryKey,
      warning: warning,
    );
  }

  factory E2eeBootstrapResult.failure(String error) {
    return E2eeBootstrapResult._(success: false, error: error);
  }
}

class E2eeService {
  final MatrixService _matrixService;
  final RecoveryKeyAcknowledgementStore _acknowledgements;

  E2eeService(
    this._matrixService, {
    RecoveryKeyAcknowledgementStore acknowledgements =
        const RecoveryKeyAcknowledgementStore(),
  }) : _acknowledgements = acknowledgements;

  Client get _client => _matrixService.client;

  Encryption? get _encryption => _client.encryption;

  Future<E2eeStatus> getStatus() async {
    final encryption = _encryption;
    final vodozemacActive = _matrixService.isVodozemacActive;
    if (encryption == null || !encryption.enabled) {
      return E2eeStatus(
        available: false,
        vodozemacEngineActive: vodozemacActive,
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

    final recoveryKeyId = encryption.ssss.defaultKeyId;
    final recoveryKeyData = recoveryKeyId == null
        ? null
        : encryption.ssss.getKey(recoveryKeyId);
    final userId = _client.userID;
    final recoverySavedConfirmed = userId != null && recoveryKeyId != null
        ? await _acknowledgements.isSaved(userId: userId, keyId: recoveryKeyId)
        : false;

    return E2eeStatus(
      available: true,
      vodozemacEngineActive: vodozemacActive,
      crossSigningEnabled: encryption.crossSigning.enabled,
      crossSigningCached: crossSigningCached,
      keyBackupEnabled: encryption.keyManager.enabled,
      keyBackupCached: keyBackupCached,
      defaultRecoveryKeyId: recoveryKeyId,
      deviceId: _client.deviceID,
      identityKey: _client.identityKey,
      fingerprintKey: _client.fingerprintKey,
      recoveryConfigured: recoveryKeyData != null,
      recoveryHasPassphrase: recoveryKeyData?.passphrase != null,
      recoverySavedConfirmed: recoverySavedConfirmed,
    );
  }

  Future<E2eeBootstrapResult> setupRecoveryAndKeyBackup({
    String? passphrase,
    String? existingRecoveryCredential,
    Future<String?> Function()? requestAccountPassword,
    Future<bool> Function(UiaRequest request)? requestSsoAuthentication,
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
    String? authenticationError;
    final pendingUiaRequests = <UiaRequest>{};
    final errorSubscription = _client.onEncryptionError.stream.listen((error) {
      lastEncryptionError = error;
    });
    final uiaSubscription = _client.onUiaRequest.stream.listen((request) {
      if (request.state != UiaRequestState.waitForUser ||
          !pendingUiaRequests.add(request)) {
        return;
      }
      unawaited(() async {
        try {
          while (request.state == UiaRequestState.waitForUser) {
            if (request.nextStages.contains(AuthenticationTypes.dummy)) {
              await request.completeStage(
                AuthenticationData(
                  type: AuthenticationTypes.dummy,
                  session: request.session,
                ),
              );
              continue;
            }

            if (request.nextStages.contains(AuthenticationTypes.sso) &&
                requestSsoAuthentication != null) {
              final completed = await requestSsoAuthentication(request);
              if (!completed) {
                authenticationError =
                    'Secure account confirmation was cancelled.';
                request.cancel(Exception(authenticationError));
                return;
              }
              await request.completeStage(
                AuthenticationData(session: request.session),
              );
              continue;
            }

            if (!request.nextStages.contains(AuthenticationTypes.password)) {
              authenticationError =
                  'The XMO account server requested an unsupported authentication method.';
              request.cancel(Exception(authenticationError));
              return;
            }

            final password = await requestAccountPassword?.call();
            if (password == null || password.isEmpty) {
              authenticationError =
                  'Account password confirmation was cancelled.';
              request.cancel(Exception(authenticationError));
              return;
            }

            await request.completeStage(
              AuthenticationPassword(
                session: request.session,
                password: password,
                identifier: AuthenticationUserIdentifier(user: _client.userID!),
              ),
            );
          }
        } catch (error, stackTrace) {
          debugPrint(
            '[E2EE] Interactive authentication failed: '
            '$error\n$stackTrace',
          );
          authenticationError = _formatException(error);
          if (request.state != UiaRequestState.done &&
              request.state != UiaRequestState.fail) {
            request.cancel(Exception(authenticationError));
          }
        } finally {
          pendingUiaRequests.remove(request);
        }
      }());
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
            final existingKey = bootstrap.newSsssKey;
            final credential = existingRecoveryCredential?.trim();
            if (existingKey == null ||
                credential == null ||
                credential.isEmpty) {
              return E2eeBootstrapResult.failure(
                'Enter the existing recovery key or passphrase first.',
              );
            }
            await existingKey.unlock(
              keyOrPassphrase: credential,
              postUnlock: false,
            );
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
              passphrase?.trim().isEmpty == true ? null : passphrase?.trim(),
            );
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
              _formatBootstrapError(
                lastEncryptionError,
                authenticationError: authenticationError,
              ),
            );
        }
      }
    } catch (e, s) {
      debugPrint('[E2EE] Recovery setup failed: $e\n$s');
      return E2eeBootstrapResult.failure(_formatException(e));
    } finally {
      await errorSubscription.cancel();
      await uiaSubscription.cancel();
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

  Future<E2eeBootstrapResult> verifyRecoveryCredential(
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
      await recovery.unlock(
        keyOrPassphrase: keyOrPassphrase.trim(),
        postUnlock: false,
      );
      return E2eeBootstrapResult.success();
    } catch (e, s) {
      debugPrint('[E2EE] Recovery credential verification failed: $e\n$s');
      return E2eeBootstrapResult.failure(
        'Recovery key or passphrase is invalid.',
      );
    }
  }

  Future<E2eeBootstrapResult> revealRecoveryKey(String passphrase) async {
    final encryption = _encryption;
    if (encryption == null || !encryption.enabled) {
      return E2eeBootstrapResult.failure(
        'Encryption is not available on this session.',
      );
    }
    try {
      final recovery = encryption.ssss.open();
      if (!recovery.hasPassphrase) {
        return E2eeBootstrapResult.failure(
          'This recovery key cannot be recreated. Use your saved copy.',
        );
      }
      await recovery.unlock(passphrase: passphrase.trim(), postUnlock: false);
      return E2eeBootstrapResult.success(recoveryKey: recovery.recoveryKey);
    } catch (e, s) {
      debugPrint('[E2EE] Recovery key reveal failed: $e\n$s');
      return E2eeBootstrapResult.failure('Recovery passphrase is invalid.');
    }
  }

  Future<E2eeBootstrapResult> rotateRecoveryKey({
    required String currentCredential,
    String? newPassphrase,
  }) async {
    final encryption = _encryption;
    if (encryption == null || !encryption.enabled) {
      return E2eeBootstrapResult.failure(
        'Encryption is not available on this session.',
      );
    }

    OpenSSSS? replacement;
    var defaultKeyChanged = false;
    try {
      await _prepareBootstrapSyncState();
      final current = encryption.ssss.open();
      await current.unlock(
        keyOrPassphrase: currentCredential.trim(),
        postUnlock: false,
      );

      final encryptedSecrets = encryption.ssss
          .analyzeEncryptedSecrets()
          .keys
          .toSet();
      replacement = await encryption.ssss.createKey(
        newPassphrase?.trim().isEmpty == true ? null : newPassphrase?.trim(),
        'XMO recovery',
      );
      await encryption.ssss.migrateSecretsToKey(
        primaryUnlockedKey: current,
        destinationKey: replacement,
        unlockCredential: currentCredential.trim(),
      );

      final migratedSecrets = <String, String>{};
      for (final type in encryptedSecrets) {
        migratedSecrets[type] = await replacement.getStored(type);
      }

      await encryption.ssss.setDefaultKeyId(replacement.keyId);
      defaultKeyChanged = true;

      String? cleanupWarning;
      try {
        for (final entry in migratedSecrets.entries) {
          await replacement.validateAndStripOtherKeys(entry.key, entry.value);
        }
        await replacement.maybeCacheAll();
      } catch (e, s) {
        debugPrint('[E2EE] Old recovery-key cleanup deferred: $e\n$s');
        cleanupWarning =
            'The new key is active, but old key cleanup will be retried later.';
      }

      final userId = _client.userID;
      if (userId != null) await _acknowledgements.clear(userId);
      return E2eeBootstrapResult.success(
        recoveryKey: replacement.recoveryKey,
        warning: cleanupWarning,
      );
    } catch (e, s) {
      debugPrint('[E2EE] Recovery key rotation failed: $e\n$s');
      if (defaultKeyChanged && replacement?.recoveryKey != null) {
        return E2eeBootstrapResult.success(
          recoveryKey: replacement!.recoveryKey,
          warning:
              'The new key is active, but recovery cleanup did not finish.',
        );
      }
      return E2eeBootstrapResult.failure(
        'Recovery key replacement failed. The current key is still active.',
      );
    }
  }

  Future<void> markCurrentRecoveryKeySaved() async {
    final userId = _client.userID;
    final keyId = _encryption?.ssss.defaultKeyId;
    if (userId == null || keyId == null) return;
    await _acknowledgements.markSaved(userId: userId, keyId: keyId);
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

  String _formatBootstrapError(SdkError? error, {String? authenticationError}) {
    if (authenticationError?.isNotEmpty == true) {
      return authenticationError!;
    }
    if (error?.exception != null) {
      return _formatException(error!.exception);
    }
    return 'Recovery setup failed while creating cross-signing or key backup. Try again after syncing finishes.';
  }

  String _formatException(Object? exception) {
    return userFacingError(
      exception,
      fallback: 'Recovery setup failed. Try again after syncing finishes.',
    );
  }
}
