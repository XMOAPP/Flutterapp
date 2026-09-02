import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xmo_auth_server/src/thirdweb_payment_gateway.dart';

const _sender = '0x1111111111111111111111111111111111111111';
const _receiver = '0x2222222222222222222222222222222222222222';

void main() {
  test('prepares and validates a Base USDC Thirdweb payment', () async {
    final gateway = ThirdwebPaymentGateway(
      secretKey: 'secret',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/buy/prepare');
        expect(request.headers['x-secret-key'], 'secret');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['paymentLinkId'], 'payment-1');
        expect(body['sender'], _sender);
        return http.Response(jsonEncode(_preparedResponse()), 200);
      }),
    );
    final prepared = await gateway.prepareBaseUsdcPayment(
      paymentLinkId: 'payment-1',
      amount: BigInt.from(5000000),
      sender: _sender,
      receiver: _receiver,
      purchaseData: const {'donationId': 'donation-1'},
    );
    expect(prepared.destinationAmount, BigInt.from(5000000));
    expect(prepared.transactions.single.chainId, 8453);
  });

  test('rejects a Thirdweb quote that changes destination amount', () async {
    final response = _preparedResponse();
    (response['data'] as Map<String, Object?>)['destinationAmount'] = '1';
    final gateway = ThirdwebPaymentGateway(
      secretKey: 'secret',
      client: MockClient((_) async => http.Response(jsonEncode(response), 200)),
    );
    await expectLater(
      gateway.prepareBaseUsdcPayment(
        paymentLinkId: 'payment-1',
        amount: BigInt.from(5000000),
        sender: _sender,
        receiver: _receiver,
        purchaseData: const {},
      ),
      throwsA(isA<ThirdwebGatewayException>()),
    );
  });
}

Map<String, Object?> _preparedResponse() => {
  'data': <String, Object?>{
    'originAmount': '5000000',
    'destinationAmount': '5000000',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'expiration': DateTime.now()
        .add(const Duration(minutes: 4))
        .millisecondsSinceEpoch,
    'steps': [
      {
        'transactions': [
          {
            'id': 'transaction-1',
            'action': 'transaction',
            'chainId': 8453,
            'to': _receiver,
            'data': '0x00',
            'value': '0',
          },
        ],
      },
    ],
  },
};
