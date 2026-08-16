import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xmo/services/wallet_auth_service.dart';

void main() {
  group('WalletAuthService wallet-only accounts', () {
    test('looks up an existing wallet account', () async {
      final service = WalletAuthService(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, endsWith('/account'));
          expect(jsonDecode(request.body), {
            'address': '0xabc',
            'walletType': 'evm',
          });
          return http.Response(
            jsonEncode({'exists': true, 'username': 'alice'}),
            200,
          );
        }),
      );

      final account = await service.lookupAccount(
        address: '0xabc',
        walletType: 'evm',
      );

      expect(account.exists, isTrue);
      expect(account.username, 'alice');
    });

    test('checks wallet username availability', () async {
      final service = WalletAuthService(
        httpClient: MockClient((request) async {
          expect(request.url.path, endsWith('/username-availability'));
          expect(jsonDecode(request.body), {'username': 'alice'});
          return http.Response(jsonEncode({'available': false}), 200);
        }),
      );

      expect(await service.isUsernameAvailable('alice'), isFalse);
    });

    test('keeps the server-selected challenge mode and username', () async {
      final service = WalletAuthService(
        httpClient: MockClient((request) async {
          expect(request.url.path, endsWith('/nonce'));
          return http.Response(
            jsonEncode({
              'message': 'Sign this message',
              'nonce': 'one-time-nonce',
              'expiresAt': '2026-08-16T12:00:00Z',
              'mode': 'create',
              'username': 'alice',
            }),
            200,
          );
        }),
      );

      final challenge = await service.createChallenge(
        username: 'alice',
        address: '0xabc',
        mode: 'login',
        walletType: 'evm',
      );

      expect(challenge.mode, 'create');
      expect(challenge.username, 'alice');
      expect(challenge.nonce, 'one-time-nonce');
    });

    test('sends the nonce and returns the Matrix JWT login token', () async {
      final service = WalletAuthService(
        httpClient: MockClient((request) async {
          expect(request.url.path, endsWith('/verify'));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['nonce'], 'one-time-nonce');
          expect(body.containsKey('matrixPassword'), isFalse);
          return http.Response(
            jsonEncode({
              'username': 'alice',
              'address': '0xabc',
              'walletType': 'evm',
              'matrixLoginToken': 'short-lived-jwt',
            }),
            200,
          );
        }),
      );

      final result = await service.verifySignature(
        username: 'alice',
        address: '0xabc',
        mode: 'login',
        walletType: 'evm',
        message: 'Sign this message',
        signature: '0xsigned',
        nonce: 'one-time-nonce',
      );

      expect(result.matrixLoginToken, 'short-lived-jwt');
    });
  });
}
