import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Matrix SDK database uses SQLCipher with a secure-storage key', () {
    final service = File('lib/services/matrix_service.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('sqflite_sqlcipher:'));
    expect(service, contains("package:sqflite_sqlcipher/sqflite.dart"));
    expect(service, contains("'xmo_matrix_database_key_v1'"));
    expect(
      service,
      contains('rawQuery("SELECT sqlcipher_export(\'encrypted\')")'),
    );
    expect(
      service,
      isNot(contains('execute("SELECT sqlcipher_export(\'encrypted\')")')),
    );
    expect(service, contains("'\$path.plaintext-backup'"));
    expect(service, contains('_quarantineUnreadableMatrixDatabase(path)'));
    expect(service, contains("'matrix_xmo_recovery'"));
    expect(service, contains("_deleteFileIfPresent('\$path-wal')"));
    expect(service, contains('openDatabase(path, password: cipher)'));
    expect(service, isNot(contains("package:sqflite/sqflite.dart")));
  });
}
