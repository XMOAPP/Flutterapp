import 'dart:convert';
import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmo_auth_server/src/wallet_auth_service.dart';

void main() {
  group('WalletAuthConfig production origin', () {
    test('fails closed when the wallet origin is absent', () {
      final config = WalletAuthConfig.fromEnvironment({
        'XMO_WALLET_JWT_SECRET': 'a' * 32,
        'XMO_WALLET_JWT_ISSUER': 'xmo-wallet-auth',
        'XMO_WALLET_JWT_AUDIENCE': 'xmo-matrix',
      });

      expect(config.domain, isEmpty);
      expect(config.uri, isEmpty);
      expect(config.isConfigured, isFalse);
    });

    test('requires an HTTPS URI for the configured signing domain', () {
      final invalidConfigs = <WalletAuthConfig>[
        const WalletAuthConfig(
          jwtSecret: 'test-wallet-secret-that-is-long-enough-for-hmac',
          jwtIssuer: 'xmo-wallet-auth',
          jwtAudience: 'xmo-matrix',
          domain: 'xmo.dpdns.org',
          uri: 'http://xmo.dpdns.org',
          statement: 'Sign in to XMO.',
        ),
        const WalletAuthConfig(
          jwtSecret: 'test-wallet-secret-that-is-long-enough-for-hmac',
          jwtIssuer: 'xmo-wallet-auth',
          jwtAudience: 'xmo-matrix',
          domain: 'xmo.dpdns.org',
          uri: 'https://other.example',
          statement: 'Sign in to XMO.',
        ),
      ];

      for (final config in invalidConfigs) {
        expect(config.isConfigured, isFalse);
      }
    });
  });

  group('WalletAuthService username rules', () {
    test('normalizes capitals and rejects punctuation', () {
      expect(WalletAuthService.normalizeUsername('Alice01'), 'alice01');
      expect(
        () => WalletAuthService.normalizeUsername('alice_01'),
        throwsA(isA<WalletAuthException>()),
      );
    });
  });

  test('verifies a personal_sign challenge and issues a short JWT', () async {
    final service = WalletAuthService(
      config: const WalletAuthConfig(
        jwtSecret: 'test-wallet-secret-that-is-long-enough-for-hmac',
        jwtIssuer: 'xmo-wallet-auth',
        jwtAudience: 'xmo-matrix',
        domain: 'xmo.test',
        uri: 'https://xmo.test',
        statement: 'Sign in to XMO.',
      ),
    );
    final credentials = EthPrivateKey.fromHex(
      '0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    final address = credentials.address.with0x;

    final challenge = service.createChallenge(
      username: 'alice',
      address: address,
      mode: 'login',
    );
    final signature = credentials.signPersonalMessageToUint8List(
      utf8.encode(challenge.message),
    );

    await service.verify(
      challenge: challenge,
      username: 'alice',
      address: address,
      message: challenge.message,
      signature: bytesToHex(signature, include0x: true),
      mode: 'login',
    );

    final token = service.issueMatrixLoginToken('alice');
    final parts = token.split('.');
    expect(parts, hasLength(3));
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
    expect(claims['sub'], 'alice');
    expect(claims['iss'], 'xmo-wallet-auth');
    expect(claims['aud'], 'xmo-matrix');
    expect((claims['exp'] as int) - (claims['iat'] as int), 60);
  });

  test(
    'includes only the configured public XMO origin in the signing prompt',
    () {
      final service = WalletAuthService(
        config: const WalletAuthConfig(
          jwtSecret: 'test-wallet-secret-that-is-long-enough-for-hmac',
          jwtIssuer: 'xmo-wallet-auth',
          jwtAudience: 'xmo-matrix',
          domain: 'xmo.dpdns.org',
          uri: 'https://xmo.dpdns.org',
          statement: 'Sign in to XMO.',
        ),
      );

      final challenge = service.createChallenge(
        username: 'alice',
        address: '0x0000000000000000000000000000000000000001',
        mode: 'login',
      );

      expect(challenge.message, contains('xmo.dpdns.org wants you to sign in'));
      expect(challenge.message, contains('URI: https://xmo.dpdns.org'));
      expect(
        challenge.message,
        isNot(contains('centralindia.cloudapp.azure.com')),
      );
    },
  );

  test('verifies Solana Ed25519 challenge', () async {
    final service = WalletAuthService(
      config: const WalletAuthConfig(
        jwtSecret: 'test-wallet-secret-that-is-long-enough-for-hmac',
        jwtIssuer: 'xmo-wallet-auth',
        jwtAudience: 'xmo-matrix',
        domain: 'xmo.test',
        uri: 'https://xmo.test',
        statement: 'Sign in to XMO.',
      ),
    );
    final ed25519 = Ed25519();
    final keyPair = await ed25519.newKeyPairFromSeed(
      List<int>.generate(32, (index) => index + 1),
    );
    final publicKey = await keyPair.extractPublicKey();
    final address = base58.encode(Uint8List.fromList(publicKey.bytes));

    final challenge = service.createChallenge(
      username: 'alice',
      address: address,
      mode: 'login',
      walletType: WalletAuthTypes.solana,
      chainId: 'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp',
    );
    final signature = await ed25519.sign(
      utf8.encode(challenge.message),
      keyPair: keyPair,
    );

    await service.verify(
      challenge: challenge,
      username: 'alice',
      address: address,
      message: challenge.message,
      signature: base58.encode(Uint8List.fromList(signature.bytes)),
      mode: 'login',
      walletType: WalletAuthTypes.solana,
    );
  });

  test('requires a strong server secret', () {
    final service = WalletAuthService(
      config: const WalletAuthConfig(
        jwtSecret: 'short',
        jwtIssuer: 'xmo-wallet-auth',
        jwtAudience: 'xmo-matrix',
        domain: 'xmo.test',
        uri: 'https://xmo.test',
        statement: 'Sign in to XMO.',
      ),
    );

    expect(
      () => service.createChallenge(
        username: 'alice',
        address: '0x0000000000000000000000000000000000000001',
        mode: 'login',
      ),
      throwsA(isA<WalletAuthException>()),
    );
  });

  test('rejects a signature for a different challenge', () async {
    final service = WalletAuthService(
      config: const WalletAuthConfig(
        jwtSecret: 'test-wallet-secret-that-is-long-enough-for-hmac',
        jwtIssuer: 'xmo-wallet-auth',
        jwtAudience: 'xmo-matrix',
        domain: 'xmo.test',
        uri: 'https://xmo.test',
        statement: 'Sign in to XMO.',
      ),
    );
    final credentials = EthPrivateKey.fromHex(
      '0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    final challenge = service.createChallenge(
      username: 'alice',
      address: credentials.address.with0x,
      mode: 'login',
    );
    final alteredMessage = '${challenge.message} changed';
    final signature = credentials.signPersonalMessageToUint8List(
      utf8.encode(alteredMessage),
    );
    await expectLater(
      service.verify(
        challenge: challenge,
        username: 'alice',
        address: credentials.address.with0x,
        message: alteredMessage,
        signature: bytesToHex(signature, include0x: true),
        mode: 'login',
      ),
      throwsA(isA<WalletAuthException>()),
    );
  });
}
