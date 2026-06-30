import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xmo/services/e2ee_service.dart';
import 'package:xmo/services/matrix_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const username = String.fromEnvironment('XMO_TEST_USERNAME');
  const password = String.fromEnvironment('XMO_TEST_PASSWORD');
  const requireE2ee = bool.fromEnvironment('XMO_TEST_REQUIRE_E2EE');

  testWidgets('real Matrix account can login, report E2EE state, and logout',
      (tester) async {
    if (username.isEmpty || password.isEmpty) {
      markTestSkipped(
        'Set XMO_TEST_USERNAME and XMO_TEST_PASSWORD to run this real-account Android test.',
      );
      return;
    }

    final service = MatrixService();
    await service.init();

    try {
      await service.login(username, password);
      expect(service.isLoggedIn, isTrue);
      expect(service.userId, isNotEmpty);

      final status = await E2eeService(service).getStatus();
      if (requireE2ee) {
        expect(status.available, isTrue);
        expect(status.deviceId, isNotEmpty);
        expect(status.identityKey, isNotEmpty);
        expect(status.fingerprintKey, isNotEmpty);
      }
    } finally {
      if (service.isLoggedIn) {
        await service.logout();
      }
    }

    expect(service.isLoggedIn, isFalse);
  });
}
