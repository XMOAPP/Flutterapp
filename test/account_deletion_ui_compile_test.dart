import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/config/app_config.dart';
import 'package:xmo/screens/app_settings_screen.dart';

void main() {
  test('account deletion UI and production URLs compile together', () {
    expect(DeleteAccountScreen, isNotNull);
    expect(Uri.parse(AppConfig.accountDeletionServerUrl).isScheme('https'),
        isTrue);
    expect(
        Uri.parse(AppConfig.accountDeletionWebUrl).isScheme('https'), isTrue);
  });
}
