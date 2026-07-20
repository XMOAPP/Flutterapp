import 'dart:convert';
import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmo_auth_server/src/wallet_auth_service.dart';

void main() {
  test('verifies personal_sign challenge and rejects replay', () async {
    final service = WalletAuthService(
      config: const WalletAuthConfig(
        secret: 'test-wallet-secret-that-is-long-enough-for-hmac',
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

    final verification = await service.verify(
      username: 'alice',
      address: address,
      message: challenge.message,
      signature: bytesToHex(signature, include0x: true),
      mode: 'login',
    );

    expect(verification.username, 'alice');
    expect(verification.address, address.toLowerCase());
    expect(verification.matrixPassword, startsWith('xmo_wallet_v1_'));
    await expectLater(
      service.verify(
        username: 'alice',
        address: address,
        message: challenge.message,
        signature: bytesToHex(signature, include0x: true),
        mode: 'login',
      ),
      throwsA(isA<WalletAuthException>()),
    );
  });

  test('verifies Solana Ed25519 challenge', () async {
    final service = WalletAuthService(
      config: const WalletAuthConfig(
        secret: 'test-wallet-secret-that-is-long-enough-for-hmac',
        domain: 'xmo.test',
        uri: 'https://xmo.test',
        statement: 'Sign in to XMO.',
      ),
    );
    final ed25519 = Ed25519();
    final keyPair = await ed25519.newKeyPairFromSeed(List<int>.generate(
      32,
      (index) => index + 1,
    ));
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

    final verification = await service.verify(
      username: 'alice',
      address: address,
      message: challenge.message,
      signature: base58.encode(Uint8List.fromList(signature.bytes)),
      mode: 'login',
      walletType: WalletAuthTypes.solana,
    );

    expect(verification.username, 'alice');
    expect(verification.address, address);
    expect(verification.walletType, WalletAuthTypes.solana);
    expect(verification.matrixPassword, startsWith('xmo_wallet_v1_'));
  });

  test('requires a strong server secret', () {
    final service = WalletAuthService(
      config: const WalletAuthConfig(
        secret: 'short',
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
}
