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
    expect(provider, contains('XMO secure storage could not start'));
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
    expect(
      service,
      contains('Reusing the current Matrix session for wallet login.'),
    );
    expect(service, contains('Switching Matrix account for wallet login.'));
    expect(
      service,
      contains('if (_client.isLogged() && _client.userID == userId)'),
    );
    expect(service, contains('waitUntilLoadCompletedLoaded: false'));
    expect(service, contains("'device_id': requestedDeviceId"));
    expect(service, contains("'xmo_matrix_device_id_v1'"));
  });

  test('SSO and wallet logins reuse the installed app device ID', () {
    final service = File('lib/services/matrix_service.dart').readAsStringSync();

    final ssoLogin = service.indexOf('Future<void> loginWithSsoToken');
    final walletLogin = service.indexOf('Future<void> loginWithWalletToken');
    expect(ssoLogin, greaterThanOrEqualTo(0));
    expect(walletLogin, greaterThan(ssoLogin));
    expect(
      service.indexOf(
        'final deviceId = await _getOrCreateMatrixDeviceId();',
        ssoLogin,
      ),
      greaterThan(ssoLogin),
    );
    expect(
      service.indexOf('deviceId: deviceId,', ssoLogin),
      greaterThan(ssoLogin),
    );
    expect(
      service.indexOf(
        'final requestedDeviceId = await _getOrCreateMatrixDeviceId();',
        walletLogin,
      ),
      greaterThan(walletLogin),
    );
  });

  test(
    'logout revokes the Matrix device even when encryption key upload fails',
    () {
      final service = File(
        'lib/services/matrix_service.dart',
      ).readAsStringSync();
      final logout = service.indexOf('Future<void> logout() async');

      expect(logout, greaterThanOrEqualTo(0));
      expect(
        service.indexOf('await _logoutRemoteSession(token);', logout),
        greaterThan(logout),
      );
      expect(
        service.indexOf("path: '/_matrix/client/v3/logout'"),
        greaterThanOrEqualTo(0),
      );
      expect(
        service.indexOf('await _client.clear();', logout),
        greaterThan(logout),
      );
    },
  );

  test('wallet post-login setup cannot invalidate authentication', () {
    final provider = File(
      'lib/providers/matrix_provider.dart',
    ).readAsStringSync();
    final sessionReady = provider.indexOf(
      '_startAuthenticatedSession();',
      provider.indexOf('Future<bool> loginWithWalletToken'),
    );
    final setup = provider.indexOf(
      'unawaited(_completeWalletLoginSetup())',
      sessionReady,
    );

    expect(sessionReady, greaterThanOrEqualTo(0));
    expect(setup, greaterThan(sessionReady));
    expect(provider, contains(r'Wallet post-login ${step.$1} setup failed'));
  });

  test('every authenticated session initializes call support before sync', () {
    final provider = File(
      'lib/providers/matrix_provider.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(provider, contains('void _startAuthenticatedSession()'));
    final callback = provider.indexOf('_onAuthenticatedSessionReady?.call();');
    final sync = provider.indexOf('_svc.startSync();', callback);
    expect(callback, greaterThanOrEqualTo(0));
    expect(sync, greaterThan(callback));
    expect(main, contains('onAuthenticatedSessionReady: ()'));
    expect(main, contains('VoipService().init('));
  });
}
