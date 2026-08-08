import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class FlutterSecureValueStore implements SecureValueStore {
  const FlutterSecureValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Opens an encrypted Hive box and migrates a legacy plaintext box through an
/// encrypted staging box. The staging box survives an interrupted migration.
class EncryptedHiveBoxStore {
  const EncryptedHiveBoxStore({
    required this.boxName,
    required this.stagingBoxName,
    required this.keyName,
    required this.secureValues,
  });

  final String boxName;
  final String stagingBoxName;
  final String keyName;
  final SecureValueStore secureValues;

  String get _migrationStateKey => '${keyName}_migration_state_v1';

  Future<Box<dynamic>> open() async {
    final keyResult = await _loadOrCreateKey();
    final cipher = HiveAesCipher(keyResult.key);

    if (await Hive.boxExists(stagingBoxName)) {
      final restored = await _restoreFromStaging(cipher);
      await _writeMigrationState('encrypted');
      return restored;
    }

    final state = await _readMigrationState();
    if (state == 'plaintext' || keyResult.created) {
      return _migratePlaintextBox(cipher);
    }

    try {
      final encrypted = await Hive.openBox<dynamic>(
        boxName,
        encryptionCipher: cipher,
      );
      await _writeMigrationState('encrypted');
      return encrypted;
    } catch (encryptedOpenError) {
      throw StateError(
        'The encrypted authentication store could not be opened. Existing '
        'session data was preserved: $encryptedOpenError',
      );
    }
  }

  Future<_EncryptionKeyResult> _loadOrCreateKey() async {
    String? encodedKey;
    var created = false;
    try {
      encodedKey = await secureValues.read(keyName);
    } catch (error) {
      throw StateError('Could not read the local encryption key: $error');
    }

    if (encodedKey == null || encodedKey.isEmpty) {
      await _writeMigrationState('plaintext');
      encodedKey = base64.encode(Hive.generateSecureKey());
      created = true;
      try {
        await secureValues.write(keyName, encodedKey);
        if (await secureValues.read(keyName) != encodedKey) {
          throw const FormatException('Encryption key verification failed');
        }
      } catch (error) {
        throw StateError('Could not persist the local encryption key: $error');
      }
    }

    try {
      final key = base64.decode(encodedKey);
      if (key.length != 32) {
        throw const FormatException('Expected a 256-bit encryption key');
      }
      return _EncryptionKeyResult(key: key, created: created);
    } on FormatException catch (error) {
      throw StateError('The local encryption key is invalid: $error');
    }
  }

  Future<Box<dynamic>> _migratePlaintextBox(HiveAesCipher cipher) async {
    if (!await Hive.boxExists(boxName)) {
      final encrypted = await Hive.openBox<dynamic>(
        boxName,
        encryptionCipher: cipher,
      );
      await _writeMigrationState('encrypted');
      return encrypted;
    }

    Box<dynamic> plaintextBox;
    try {
      plaintextBox = await Hive.openBox<dynamic>(boxName);
    } catch (error) {
      throw StateError(
        'The plaintext authentication store could not be opened for safe '
        'migration. Existing session data was preserved: $error',
      );
    }

    final snapshot = Map<dynamic, dynamic>.from(plaintextBox.toMap());
    final stagingBox = await Hive.openBox<dynamic>(
      stagingBoxName,
      encryptionCipher: cipher,
    );
    await stagingBox.clear();
    await stagingBox.putAll(snapshot);
    _verifySnapshot(stagingBox, snapshot);
    await stagingBox.close();
    await plaintextBox.close();

    await Hive.deleteBoxFromDisk(boxName);
    final encryptedBox = await Hive.openBox<dynamic>(
      boxName,
      encryptionCipher: cipher,
    );
    await encryptedBox.putAll(snapshot);
    _verifySnapshot(encryptedBox, snapshot);
    await _writeMigrationState('encrypted');
    await Hive.deleteBoxFromDisk(stagingBoxName);
    return encryptedBox;
  }

  Future<Box<dynamic>> _restoreFromStaging(HiveAesCipher cipher) async {
    final stagingBox = await Hive.openBox<dynamic>(
      stagingBoxName,
      encryptionCipher: cipher,
    );
    final snapshot = Map<dynamic, dynamic>.from(stagingBox.toMap());
    await stagingBox.close();

    await Hive.deleteBoxFromDisk(boxName);
    final encryptedBox = await Hive.openBox<dynamic>(
      boxName,
      encryptionCipher: cipher,
    );
    await encryptedBox.putAll(snapshot);
    _verifySnapshot(encryptedBox, snapshot);
    await Hive.deleteBoxFromDisk(stagingBoxName);
    return encryptedBox;
  }

  void _verifySnapshot(Box<dynamic> box, Map<dynamic, dynamic> expected) {
    if (box.length != expected.length) {
      throw StateError('Authentication store migration verification failed');
    }
    for (final entry in expected.entries) {
      if (!box.containsKey(entry.key) ||
          !_valuesEqual(box.get(entry.key), entry.value)) {
        throw StateError('Authentication store migration verification failed');
      }
    }
  }

  bool _valuesEqual(Object? first, Object? second) {
    if (identical(first, second) || first == second) return true;
    if (first is Uint8List && second is Uint8List) {
      return _listsEqual(first, second);
    }
    if (first is List && second is List) return _listsEqual(first, second);
    if (first is Map && second is Map) {
      if (first.length != second.length) return false;
      for (final entry in first.entries) {
        if (!second.containsKey(entry.key) ||
            !_valuesEqual(entry.value, second[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  bool _listsEqual(List<dynamic> first, List<dynamic> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_valuesEqual(first[index], second[index])) return false;
    }
    return true;
  }

  Future<String?> _readMigrationState() async {
    try {
      return await secureValues.read(_migrationStateKey);
    } catch (error) {
      throw StateError('Could not read authentication migration state: $error');
    }
  }

  Future<void> _writeMigrationState(String value) async {
    try {
      await secureValues.write(_migrationStateKey, value);
      if (await secureValues.read(_migrationStateKey) != value) {
        throw const FormatException('Migration state verification failed');
      }
    } catch (error) {
      throw StateError(
        'Could not persist authentication migration state: $error',
      );
    }
  }
}

class _EncryptionKeyResult {
  const _EncryptionKeyResult({required this.key, required this.created});

  final List<int> key;
  final bool created;
}
