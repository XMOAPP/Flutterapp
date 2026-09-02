import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xmo/services/thirdweb_donation_service.dart';

const _token = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _recipient = '0xc1a4BF16f64f5eE26b7C73831eF8bc70f200EacB';
const _wallet = '0x1111111111111111111111111111111111111111';

void main() {
  test('creates an authenticated hosted payment', () async {
    final service = ThirdwebDonationService(
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer matrix-token');
        expect(jsonDecode(request.body), {'amountUsdcSmallestUnit': '5000000'});
        return http.Response(
          jsonEncode({
            'payment': {
              'id': 'payment-123',
              'link': 'https://pay.thirdweb.com/payment-123',
            },
          }),
          200,
        );
      }),
    );
    final payment = await service.createDonationPayment(
      amountUsdcSmallestUnit: BigInt.from(5000000),
      accessToken: 'matrix-token',
    );
    expect(payment.id, 'payment-123');
  });

  test('parses a bounded Thirdweb native payment plan', () async {
    final service = ThirdwebDonationService(
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/donations/create'));
        expect(jsonDecode(request.body), {
          'amountUsdcSmallestUnit': '5000000',
          'checkoutMode': 'native',
          'walletAddress': _wallet,
        });
        return http.Response(jsonEncode(_nativeResponse()), 200);
      }),
    );
    final donation = await service.createNativeDonationPayment(
      amountUsdcSmallestUnit: BigInt.from(5000000),
      accessToken: 'matrix-token',
      walletAddress: _wallet,
    );
    expect(donation.chainId, 8453);
    expect(donation.transactions.single.action, 'transaction');
  });

  test('rejects a prepared plan with a changed amount', () async {
    final response = _nativeResponse();
    (response['donation'] as Map<String, Object?>)['amount'] = '6000000';
    final service = ThirdwebDonationService(
      client: MockClient((_) async => http.Response(jsonEncode(response), 200)),
    );
    await expectLater(
      service.createNativeDonationPayment(
        amountUsdcSmallestUnit: BigInt.from(5000000),
        accessToken: 'matrix-token',
        walletAddress: _wallet,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'submits transaction hashes to the authenticated tracking route',
    () async {
      final service = ThirdwebDonationService(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/donations/native/submit'));
          expect(request.headers['authorization'], 'Bearer matrix-token');
          expect((jsonDecode(request.body) as Map)['donationId'], 'a' * 32);
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      );
      await service.submitNativeTransaction(
        donationId: 'a' * 32,
        transaction: ThirdwebNativeTransaction(
          id: 'tx-1',
          action: 'transaction',
          chainId: 8453,
          to: _token,
          data: '0x00',
          value: BigInt.zero,
        ),
        transactionHash: '0x${'b' * 64}',
        accessToken: 'matrix-token',
      );
    },
  );

  test('reads only a recognized donation status', () async {
    final service = ThirdwebDonationService(
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/donations/native/status'));
        expect(request.url.queryParameters['id'], 'a' * 32);
        return http.Response(
          jsonEncode({
            'donation': {'id': 'a' * 32, 'status': 'confirmed'},
          }),
          200,
        );
      }),
    );
    expect(
      await service.getNativeDonationStatus(
        donationId: 'a' * 32,
        accessToken: 'matrix-token',
      ),
      'confirmed',
    );
  });

  test('rejects a missing Matrix token before sending', () async {
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
  });
}

Map<String, Object?> _nativeResponse() => {
  'donation': <String, Object?>{
    'id': 'a' * 32,
    'paymentId': 'payment-123',
    'chainId': 8453,
    'tokenAddress': _token,
    'recipient': _recipient,
    'amount': '5000000',
    'originAmount': '5000000',
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 4))
        .toIso8601String(),
    'transactions': [
      {
        'id': 'tx-1',
        'action': 'transaction',
        'chainId': 8453,
        'to': _token,
        'data': '0x00',
        'value': '0',
      },
    ],
  },
};
