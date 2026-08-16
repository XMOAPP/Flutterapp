import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recovery key management contract', () {
    late String service;
    late String acknowledgementStore;
    late String securityUi;
    late String androidActivity;

    setUpAll(() {
      service = File('lib/services/e2ee_service.dart').readAsStringSync();
      acknowledgementStore = File(
        'lib/services/recovery_key_acknowledgement_store.dart',
      ).readAsStringSync();
      securityUi = File(
        'lib/screens/app_settings_screen.dart',
      ).readAsStringSync();
      androidActivity = File(
        'android/app/src/main/kotlin/com/xmo/xmo/MainActivity.kt',
      ).readAsStringSync();
    });

    test('never persists recovery key or passphrase', () {
      expect(acknowledgementStore, contains('markSaved'));
      expect(acknowledgementStore, contains('keyId'));
      expect(acknowledgementStore, isNot(contains('recoveryKey:')));
      expect(acknowledgementStore, isNot(contains('passphrase:')));
    });

    test('replacement verifies migration before changing the default key', () {
      final migrate = service.indexOf('migrateSecretsToKey');
      final verify = service.indexOf('replacement.getStored');
      final setDefault = service.indexOf('setDefaultKeyId');

      expect(migrate, greaterThan(-1));
      expect(verify, greaterThan(migrate));
      expect(setDefault, greaterThan(verify));
    });

    test('sensitive display uses Android screenshot protection', () {
      expect(securityUi, contains('setProtected(true)'));
      expect(securityUi, contains('setProtected(false)'));
      expect(
        androidActivity,
        contains('WindowManager.LayoutParams.FLAG_SECURE'),
      );
    });

    test('shown key requires saved acknowledgement and clears clipboard', () {
      expect(securityUi, contains('I saved this recovery key'));
      expect(securityUi, contains('Duration(seconds: 60)'));
      expect(securityUi, contains("ClipboardData(text: '')"));
    });
  });
}
