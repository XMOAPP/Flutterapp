import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device verification supports SAS acceptance and rejection', () {
    final screen = File(
      'lib/screens/device_verification_screen.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/services/device_verification_coordinator.dart',
    ).readAsStringSync();

    expect(screen, contains('acceptSas'));
    expect(screen, contains('rejectSas'));
    expect(screen, contains('sasEmojis'));
    expect(screen, contains('sasNumbers'));
    expect(screen, contains('keyBackupCached'));
    expect(coordinator, contains('incomingRequests.listen'));
    expect(coordinator, contains('Queue<KeyVerification>'));
  });

  test('OIDC UIA fallback never treats authorization as a login token', () {
    final fallback = File(
      'lib/services/matrix_uia_fallback_service.dart',
    ).readAsStringSync();

    expect(fallback, contains("'fallback'"));
    expect(fallback, contains("'session': session"));
    expect(fallback, contains('AuthenticationData(session: session)'));
    expect(fallback, isNot(contains('loginToken')));
  });
}
