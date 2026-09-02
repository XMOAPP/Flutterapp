import 'package:test/test.dart';
import 'package:xmo_auth_server/src/donation_store.dart';

void main() {
  test('donation storage reuses the wallet database by default', () {
    final config = DonationStoreConfig.fromEnvironment(const {
      'XMO_WALLET_DB_HOST': 'postgres',
      'XMO_WALLET_DB_PORT': '5433',
      'XMO_WALLET_DB_NAME': 'wallet',
      'XMO_WALLET_DB_USER': 'wallet-user',
      'XMO_WALLET_DB_PASSWORD': 'password',
    });
    expect(config.isConfigured, isTrue);
    expect(config.port, 5433);
    expect(config.database, 'wallet');
  });

  test('dedicated donation database settings take precedence', () {
    final config = DonationStoreConfig.fromEnvironment(const {
      'XMO_DONATION_DB_HOST': 'donation-db',
      'XMO_DONATION_DB_NAME': 'donations',
      'XMO_DONATION_DB_USER': 'donation-user',
      'XMO_DONATION_DB_PASSWORD': 'donation-password',
      'XMO_WALLET_DB_PASSWORD': 'wallet-password',
    });
    expect(config.host, 'donation-db');
    expect(config.database, 'donations');
    expect(config.username, 'donation-user');
    expect(config.password, 'donation-password');
  });
}
