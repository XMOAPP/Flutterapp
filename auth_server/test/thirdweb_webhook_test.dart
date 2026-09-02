import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xmo_auth_server/src/thirdweb_webhook.dart';

void main() {
  const secret = '0123456789abcdef0123456789abcdef';
  final now = DateTime.utc(2026, 9, 2, 12);
  final timestamp = now.millisecondsSinceEpoch ~/ 1000;
  const body = '{"version":2,"data":{"purchaseData":{"donationId":"abc"}}}';

  test('verifies official Thirdweb bridge webhook headers', () {
    final signature = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('$timestamp.$body')).toString();
    final result = verifyThirdwebWebhook(
      rawBody: body,
      headers: {
        'x-payload-signature': signature,
        'x-timestamp': timestamp.toString(),
      },
      secret: secret,
      now: now,
    );
    expect(result.payload['version'], 2);
    expect(result.digest, hasLength(64));
  });

  test('verifies the current Thirdweb dashboard bearer token format', () {
    final result = verifyThirdwebWebhook(
      rawBody: body,
      headers: {'authorization': 'Bearer $secret'},
      secret: secret,
      now: now,
    );
    expect(result.payload['version'], 2);
  });

  test('rejects an incorrect dashboard bearer token', () {
    expect(
      () => verifyThirdwebWebhook(
        rawBody: body,
        headers: const {'authorization': 'Bearer incorrect'},
        secret: secret,
        now: now,
      ),
      throwsFormatException,
    );
  });

  test('rejects an expired webhook even with a valid signature', () {
    final oldTimestamp = timestamp - 301;
    final signature = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('$oldTimestamp.$body')).toString();
    expect(
      () => verifyThirdwebWebhook(
        rawBody: body,
        headers: {
          'x-pay-signature': signature,
          'x-pay-timestamp': oldTimestamp.toString(),
        },
        secret: secret,
        now: now,
      ),
      throwsFormatException,
    );
  });

  test('rejects a modified payload', () {
    final signature = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('$timestamp.$body')).toString();
    expect(
      () => verifyThirdwebWebhook(
        rawBody: '${body}x',
        headers: {
          'x-payload-signature': signature,
          'x-timestamp': timestamp.toString(),
        },
        secret: secret,
        now: now,
      ),
      throwsFormatException,
    );
  });
}
