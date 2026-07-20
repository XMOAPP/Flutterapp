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
      'XMO_WALLET_AUTH_SERVER_URL',
      'XMO_STREAM_CHUNK_STORAGE',
      'XMO_AZURE_CHUNK_SIGN_URL',
      'XMO_ACCOUNT_DELETION_SERVER_URL',
      'XMO_ACCOUNT_DELETION_WEB_URL',
    ]) {
      expect(workflow, contains('vars.$variable'));
      expect(workflow, contains('--dart-define=$variable="\$$variable"'));
    }
    expect(workflow, contains('test -n "\${!variable}"'));
  });

  test('backend workflow bypasses hanging dart wrapper for analyzer', () {
    expect(workflow, contains('cache/dart-sdk/bin/dart'));
    expect(workflow, contains(r'"$DART_BIN" analyze'));
  });

  test('toolchain and jobs have deterministic bounds', () {
    expect(workflow, contains('FLUTTER_VERSION: 3.41.7'));
    expect(workflow, contains('JAVA_VERSION: "17"'));
    expect(workflow, contains('timeout-minutes:'));
    expect(workflow, contains('tools/ci/run_with_timeout.sh'));
  });

  test('format checks never rewrite source', () {
    expect(
        workflow, contains('dart format --output=none --set-exit-if-changed'));
  });

  test('backend tests are required and logs are retained', () {
    expect(workflow, contains(r'"$DART_BIN" test --reporter expanded'));
    expect(workflow, contains('uses: actions/upload-artifact@v4'));
    expect(workflow, contains('if: always()'));
    expect(workflow, contains('tools/ci/redact_logs.sh'));
  });

  test('Android smoke gate is explicit and opt-in', () {
    expect(workflow, contains('run_android_integration:'));
    expect(workflow, contains('inputs.run_android_integration'));
    expect(workflow, contains('integration_test/chat_input_smoke_test.dart'));
  });
}
