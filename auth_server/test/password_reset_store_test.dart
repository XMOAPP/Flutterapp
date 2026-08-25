import 'package:test/test.dart';
import 'package:xmo_auth_server/src/password_reset_store.dart';

void main() {
  group('PasswordResetStoreConfig', () {
    test('uses dedicated reset storage settings when configured', () {
      final config = PasswordResetStoreConfig.fromEnvironment({
        'XMO_PASSWORD_RESET_DB_HOST': 'reset-db',
        'XMO_PASSWORD_RESET_DB_PORT': '6543',
        'XMO_PASSWORD_RESET_DB_NAME': 'reset',
        'XMO_PASSWORD_RESET_DB_USER': 'reset_user',
        'XMO_PASSWORD_RESET_DB_PASSWORD': 'reset-password',
        'XMO_PASSWORD_RESET_CODE_SECRET': 'a' * 32,
      });

      expect(config.host, 'reset-db');
      expect(config.port, 6543);
      expect(config.database, 'reset');
      expect(config.username, 'reset_user');
      expect(config.isConfigured, isTrue);
    });

    test('falls back to the existing wallet database configuration', () {
      final config = PasswordResetStoreConfig.fromEnvironment({
        'XMO_WALLET_DB_HOST': 'postgres',
        'XMO_WALLET_DB_PORT': '5432',
        'XMO_WALLET_DB_NAME': 'xmo_wallet',
        'XMO_WALLET_DB_USER': 'xmo_wallet',
        'XMO_WALLET_DB_PASSWORD': 'wallet-password',
        'XMO_WALLET_JWT_SECRET': 'b' * 32,
      });

      expect(config.database, 'xmo_wallet');
      expect(config.username, 'xmo_wallet');
      expect(config.isConfigured, isTrue);
    });

    test('requires a strong secret', () {
      final config = PasswordResetStoreConfig.fromEnvironment({
        'XMO_WALLET_DB_PASSWORD': 'wallet-password',
        'XMO_WALLET_JWT_SECRET': 'short',
      });

      expect(config.isConfigured, isFalse);
    });
  });

  test('does not persist the raw reset code as its digest', () {
    final first = passwordResetCodeDigest(code: '123456', secret: 'c' * 32);
    final second = passwordResetCodeDigest(code: '123456', secret: 'c' * 32);
    final differentCode = passwordResetCodeDigest(
      code: '654321',
      secret: 'c' * 32,
    );
    final differentSecret = passwordResetCodeDigest(
      code: '123456',
      secret: 'd' * 32,
    );

    expect(first, isNot('123456'));
    expect(first, second);
    expect(first, isNot(differentCode));
    expect(first, isNot(differentSecret));
  });
}
