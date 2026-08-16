import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores only whether the user confirmed saving a recovery key.
///
/// Recovery keys and passphrases must never be persisted here.
class RecoveryKeyAcknowledgementStore {
  const RecoveryKeyAcknowledgementStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  String _storageKey(String userId) {
    final scope = base64Url.encode(utf8.encode(userId)).replaceAll('=', '');
    return 'xmo_recovery_saved_key_id_$scope';
  }

  Future<bool> isSaved({required String userId, required String keyId}) async {
    try {
      return await _storage.read(key: _storageKey(userId)) == keyId;
    } catch (_) {
      return false;
    }
  }

  Future<void> markSaved({
    required String userId,
    required String keyId,
  }) async {
    await _storage.write(key: _storageKey(userId), value: keyId);
  }

  Future<void> clear(String userId) async {
    await _storage.delete(key: _storageKey(userId));
  }
}
