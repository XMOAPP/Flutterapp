import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String workflow;
  late final String analysisOptions;

  setUpAll(() {
    workflow = File('.github/workflows/android.yml').readAsStringSync();
    analysisOptions = File('analysis_options.yaml').readAsStringSync();
  });

  test(
    'Flutter analysis excludes the independently analyzed backend package',
    () {
      expect(analysisOptions, contains('auth_server/**'));
    },
  );

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

  test(
    'release workflow writes keystore where Gradle release signing reads it',
    () {
      expect(workflow, contains('> android/upload-keystore.jks'));
      expect(workflow, contains('storeFile=upload-keystore.jks'));
      expect(workflow, isNot(contains('> android/app/upload-keystore.jks')));
    },
  );

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
      workflow,
      contains('dart format --output=none --set-exit-if-changed'),
    );
  });

  test(
    'merge workflow checks whitespace and gates internal changes on a signed bundle',
    () {
      expect(workflow, contains('git diff --check'));
      expect(workflow, contains('flutter build appbundle --release'));
      expect(
        workflow,
        contains('--dart-define=XMO_OIDC_ONLY_AUTHENTICATION=true'),
      );
    },
  );

  test('signed release job is protected from pull requests', () {
    final releaseJob = workflow.substring(
      workflow.indexOf('  release-bundle:'),
    );

    expect(workflow, contains("tags: ['v*']"));
    expect(releaseJob, contains('environment: production-release'));
    expect(releaseJob, contains("github.ref == 'refs/heads/main'"));
    expect(releaseJob, contains("startsWith(github.ref, 'refs/tags/v')"));
    expect(
      releaseJob,
      contains(
        "github.event_name == 'workflow_dispatch' && inputs.build_release",
      ),
    );
    expect(releaseJob, isNot(contains("github.event_name == 'pull_request'")));
    expect(
      releaseJob,
      isNot(
        contains(
          'github.event.pull_request.head.repo.full_name == github.repository',
        ),
      ),
    );
  });

  test('backend tests are required and logs are retained', () {
    expect(workflow, contains(r'"$DART_BIN" test --reporter expanded'));
    expect(
      workflow,
      contains(
        'uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02',
      ),
    );
    expect(workflow, contains('if: always()'));
    expect(workflow, contains('tools/ci/redact_logs.sh'));
  });

  test('Android smoke gate is explicit and opt-in', () {
    expect(workflow, contains('run_android_integration:'));
    expect(workflow, contains('inputs.run_android_integration'));
    expect(workflow, contains('integration_test/chat_input_smoke_test.dart'));
    expect(workflow, contains('android-actions/setup-android@'));
    expect(workflow, contains('tools/ci/free_android_runner_disk.sh'));
    expect(workflow, contains('sdkmanager "platform-tools"'));
    expect(
      workflow,
      contains(r'SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"'),
    );
    expect(
      workflow,
      contains(r'export ANDROID_AVD_HOME="$RUNNER_TEMP/android-avd"'),
    );
    expect(workflow, contains(r'test -x "$SDK_ROOT/emulator/emulator"'));
    expect(
      workflow,
      contains(r'"$SDK_ROOT/emulator/emulator" -list-avds | grep -Fx xmo_ci'),
    );
    expect(workflow, contains(r'nohup "$SDK_ROOT/emulator/emulator"'));
    expect(workflow, contains(r'test "$available_kb" -ge 6291456'));
  });
}
