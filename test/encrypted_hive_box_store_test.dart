import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:xmo/services/encrypted_hive_box_store.dart';

class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('write failed');
    values[key] = value;
  }
}

void main() {
  late Directory directory;
  late _MemorySecureValueStore secureValues;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xmo_hive_test_');
    Hive.init(directory.path);
    secureValues = _MemorySecureValueStore();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  EncryptedHiveBoxStore createStore() => EncryptedHiveBoxStore(
    boxName: 'auth',
    stagingBoxName: 'auth_migration',
    keyName: 'auth_key',
    secureValues: secureValues,
  );

  test(
    'migrates plaintext data and reopens it with the persisted key',
    () async {
      final plaintext = await Hive.openBox<dynamic>('auth');
      await plaintext.putAll({
        'token': 'secret-token',
        'profile': {
          'name': 'Hunter',
          'devices': [1, 2],
        },
      });
      await plaintext.close();

      final encrypted = await createStore().open();
      expect(encrypted.get('token'), 'secret-token');
      expect(encrypted.get('profile'), {
        'name': 'Hunter',
        'devices': [1, 2],
      });
      expect(await Hive.boxExists('auth_migration'), isFalse);
      await encrypted.close();

      final reopened = await createStore().open();
      expect(reopened.get('token'), 'secret-token');
    },
  );

  test('does not touch plaintext data when secure key storage fails', () async {
    final plaintext = await Hive.openBox<dynamic>('auth');
    await plaintext.put('token', 'preserve-me');
    await plaintext.close();
    secureValues.failWrites = true;

    await expectLater(createStore().open(), throwsStateError);

    final preserved = await Hive.openBox<dynamic>('auth');
    expect(preserved.get('token'), 'preserve-me');
  });

  test('recovers an interrupted migration from encrypted staging', () async {
    final key = Hive.generateSecureKey();
    secureValues.values['auth_key'] = base64.encode(key);
    final plaintext = await Hive.openBox<dynamic>('auth');
    await plaintext.put('token', 'old-value');
    await plaintext.close();
    final staging = await Hive.openBox<dynamic>(
      'auth_migration',
      encryptionCipher: HiveAesCipher(key),
    );
    await staging.put('token', 'staged-value');
    await staging.close();

    final recovered = await createStore().open();
    expect(recovered.get('token'), 'staged-value');
    expect(await Hive.boxExists('auth_migration'), isFalse);
  });

  test(
    'resumes plaintext migration after the key was already written',
    () async {
      final key = Hive.generateSecureKey();
      secureValues.values['auth_key'] = base64.encode(key);
      secureValues.values['auth_key_migration_state_v1'] = 'plaintext';
      final plaintext = await Hive.openBox<dynamic>('auth');
      await plaintext.put('token', 'resume-me');
      await plaintext.close();

      final migrated = await createStore().open();

      expect(migrated.get('token'), 'resume-me');
      expect(secureValues.values['auth_key_migration_state_v1'], 'encrypted');
    },
  );

  test('adopts an encrypted box created before migration markers', () async {
    final key = Hive.generateSecureKey();
    secureValues.values['auth_key'] = base64.encode(key);
    final encrypted = await Hive.openBox<dynamic>(
      'auth',
      encryptionCipher: HiveAesCipher(key),
    );
    await encrypted.put('token', 'already-encrypted');
    await encrypted.close();

    final reopened = await createStore().open();

    expect(reopened.get('token'), 'already-encrypted');
    expect(secureValues.values['auth_key_migration_state_v1'], 'encrypted');
  });
}
