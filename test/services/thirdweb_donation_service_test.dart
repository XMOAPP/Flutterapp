import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xmo/services/thirdweb_donation_service.dart';

void main() {
  test(
    'creates an authenticated donation payment without client identity',
    () async {
      final service = ThirdwebDonationService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.headers['authorization'],
            'Bearer matrix-access-token',
          );
          expect(request.headers['content-type'], 'application/json');
          expect(jsonDecode(request.body), {
            'amountUsdcSmallestUnit': '5000000',
          });
          return http.Response(
            jsonEncode({
              'payment': {
                'id': 'payment-123',
                'link': 'https://checkout.example.test/payment-123',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final payment = await service.createDonationPayment(
        amountUsdcSmallestUnit: BigInt.from(5000000),
        accessToken: 'matrix-access-token',
      );

      expect(payment.id, 'payment-123');
      expect(
        payment.link.toString(),
        'https://checkout.example.test/payment-123',
      );
    },
  );

  test(
    'rejects a missing Matrix access token before making a request',
    () async {
      var called = false;
      final service = ThirdwebDonationService(
        client: MockClient((_) async {
          called = true;
          return http.Response('', 500);
        }),
      );

      await expectLater(
        service.createDonationPayment(
          amountUsdcSmallestUnit: BigInt.from(5000000),
          accessToken: ' ',
        ),
        throwsA(isA<StateError>()),
      );
      expect(called, isFalse);
    },
  );

  test('rejects an insecure checkout URL returned by the server', () async {
    final service = ThirdwebDonationService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'payment': {'id': 'payment-123', 'link': 'http://checkout.test'},
          }),
          200,
        ),
      ),
    );

    await expectLater(
      service.createDonationPayment(
        amountUsdcSmallestUnit: BigInt.from(5000000),
        accessToken: 'matrix-access-token',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('creates validated Base USDC wallet transfer instructions', () async {
    final service = ThirdwebDonationService(
      client: MockClient((request) async {
        expect(jsonDecode(request.body), {
          'amountUsdcSmallestUnit': '5000000',
          'checkoutMode': 'wallet',
        });
        return http.Response(
          jsonEncode({
            'transfer': {
              'chainId': 8453,
              'tokenAddress': '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
              'recipient': '0xc1a4BF16f64f5eE26b7C73831eF8bc70f200EacB',
              'amount': '5000000',
            },
          }),
          200,
        );
      }),
    );

    final transfer = await service.createWalletDonationTransfer(
      amountUsdcSmallestUnit: BigInt.from(5000000),
      accessToken: 'matrix-access-token',
    );

    expect(transfer.chainId, 8453);
    expect(transfer.tokenAddress, '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913');
    expect(transfer.amount, BigInt.from(5000000));
  });

  test('rejects wallet transfer instructions with a changed amount', () async {
    final service = ThirdwebDonationService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'transfer': {
              'chainId': 8453,
              'tokenAddress': '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
              'recipient': '0xc1a4BF16f64f5eE26b7C73831eF8bc70f200EacB',
              'amount': '6000000',
            },
          }),
          200,
        ),
      ),
    );

    await expectLater(
      service.createWalletDonationTransfer(
        amountUsdcSmallestUnit: BigInt.from(5000000),
        accessToken: 'matrix-access-token',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
