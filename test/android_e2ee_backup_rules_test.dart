import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android backups exclude Matrix E2EE and secure-storage data', () {
    final legacy = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final modern = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    const matrixDatabaseArtifacts = <String>[
      'matrix_xmo_vodozemac_v1.db',
      'matrix_xmo_vodozemac_v1.db-wal',
      'matrix_xmo_vodozemac_v1.db-shm',
      'matrix_xmo_vodozemac_v1.db.plaintext-backup',
      'matrix_xmo_vodozemac_v1.db.encrypted',
      'matrix_xmo_vodozemac_v1.db.encrypted-wal',
      'matrix_xmo_vodozemac_v1.db.encrypted-shm',
    ];

    for (final name in matrixDatabaseArtifacts) {
      final fileRule = '<exclude domain="file" path="$name" />';
      expect(legacy, contains(fileRule));
      expect(RegExp(RegExp.escape(fileRule)).allMatches(modern).length, 2);
    }

    for (final name in <String>[
      'FlutterSecureStorage.xml',
      'flutter_secure_storage.xml',
    ]) {
      expect(legacy, contains(name));
      expect(
        RegExp('path="${RegExp.escape(name)}"').allMatches(modern).length,
        2,
      );
    }

    const recoveryRule =
        '<exclude domain="file" path="matrix_xmo_recovery/" />';
    expect(legacy, contains(recoveryRule));
    expect(RegExp(RegExp.escape(recoveryRule)).allMatches(modern).length, 2);
  });
}
