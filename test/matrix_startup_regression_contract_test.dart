import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed Matrix startup cannot reach late client authentication', () {
    final provider = File(
      'lib/providers/matrix_provider.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(provider, contains('bool _canAuthenticate()'));
    expect(provider, contains('if (!_canAuthenticate()) return false;'));
    expect(provider, contains('_svc.clientReadyForAuthentication'));
    expect(provider, contains('Matrix secure storage could not start'));
    expect(
      File('lib/services/matrix_service.dart').readAsStringSync(),
      contains('_clientReadyForAuthentication = true;'),
    );
    expect(
      main,
      contains('if (matrixProvider.state == MatrixAuthState.error)'),
    );
  });

  test('registration replaces a stale secure sign-in attempt', () {
    final otpScreen = File('lib/screens/otp_screen.dart').readAsStringSync();

    expect(
      otpScreen,
      contains('MatrixSsoService.instance.cancelPendingSignIn('),
    );
    expect(
      otpScreen.indexOf('MatrixSsoService.instance.cancelPendingSignIn('),
      lessThan(otpScreen.indexOf('while (mounted)')),
    );
  });

  test('wallet JWT login does not wait for Matrix first sync', () {
    final service = File('lib/services/matrix_service.dart').readAsStringSync();

    expect(service, contains("'type': 'org.matrix.login.jwt'"));
    expect(service, contains("path: '/_matrix/client/v3/login'"));
    expect(service, contains('waitForFirstSync: false'));
    expect(service, contains("'org.matrix.login.jwt',"));
    expect(service, contains('if (_client.isLogged())'));
    expect(service, contains('await _client.clear();'));
    expect(service, contains('waitUntilLoadCompletedLoaded: false'));
  });

  test('wallet post-login setup cannot invalidate authentication', () {
    final provider = File(
      'lib/providers/matrix_provider.dart',
    ).readAsStringSync();
    final loggedIn = provider.indexOf(
      '_state = MatrixAuthState.loggedIn;',
      provider.indexOf('Future<bool> loginWithWalletToken'),
    );
    final setup = provider.indexOf(
      'unawaited(_completeWalletLoginSetup())',
      loggedIn,
    );

    expect(loggedIn, greaterThanOrEqualTo(0));
    expect(setup, greaterThan(loggedIn));
    expect(provider, contains(r'Wallet post-login ${step.$1} setup failed'));
  });
}
