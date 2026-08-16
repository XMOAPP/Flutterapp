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

    for (final name in <String>[
      'matrix_xmo_vodozemac_v1.db',
      'matrix_xmo_vodozemac_v1.db-wal',
      'matrix_xmo_vodozemac_v1.db-shm',
      'FlutterSecureStorage.xml',
      'flutter_secure_storage.xml',
    ]) {
      expect(legacy, contains(name));
      expect(
        RegExp('path="${RegExp.escape(name)}"').allMatches(modern).length,
        2,
      );
    }
  });
}
