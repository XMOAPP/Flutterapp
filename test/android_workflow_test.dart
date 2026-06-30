import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String workflow;

  setUpAll(() {
    workflow = File('.github/workflows/android.yml').readAsStringSync();
  });

  test('release workflow validates every signing secret before building', () {
    for (final secret in const [
      'ANDROID_KEYSTORE_BASE64',
      'ANDROID_KEYSTORE_PASSWORD',
      'ANDROID_KEY_ALIAS',
      'ANDROID_KEY_PASSWORD',
    ]) {
      expect(workflow, contains('test -n "\$$secret"'));
      expect(workflow, contains('secrets.$secret'));
    }
  });

  test('release workflow writes keystore where Gradle release signing reads it',
      () {
    expect(workflow, contains('> android/upload-keystore.jks'));
    expect(workflow, contains('storeFile=upload-keystore.jks'));
    expect(workflow, isNot(contains('> android/app/upload-keystore.jks')));
  });

  test('release workflow validates release dart defines', () {
    for (final variable in const [
      'XMO_HOMESERVER_URL',
      'XMO_MATRIX_SERVER_NAME',
    ]) {
      expect(workflow, contains('vars.$variable'));
      expect(workflow, contains('test -n "\$$variable"'));
      expect(workflow, contains('--dart-define=$variable="\$$variable"'));
    }
  });

  test('backend workflow bypasses hanging dart wrapper for analyzer', () {
    expect(workflow, contains('cache/dart-sdk/bin/dart'));
    expect(workflow, contains(r'"$DART_BIN" analyze'));
  });
}
