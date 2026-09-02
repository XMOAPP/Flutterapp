import 'dart:convert';

import 'package:crypto/crypto.dart';

class ThirdwebWebhook {
  const ThirdwebWebhook({required this.payload, required this.digest});

  final Map<String, dynamic> payload;
  final String digest;
}

ThirdwebWebhook verifyThirdwebWebhook({
  required String rawBody,
  required Map<String, String> headers,
  required String secret,
  DateTime? now,
  Duration tolerance = const Duration(minutes: 5),
}) {
  final signature =
      headers['x-payload-signature'] ?? headers['x-pay-signature'];
  final timestampRaw = headers['x-timestamp'] ?? headers['x-pay-timestamp'];
  final timestamp = int.tryParse(timestampRaw ?? '');
  if (signature != null || timestampRaw != null) {
    _verifyHmac(
      rawBody: rawBody,
      secret: secret,
      signature: signature,
      timestampRaw: timestampRaw,
      timestamp: timestamp,
      now: now,
      tolerance: tolerance,
    );
  } else {
    _verifyBearerToken(headers['authorization'], secret);
  }

  final decoded = jsonDecode(rawBody);
  if (decoded is! Map) {
    throw const FormatException('Invalid Thirdweb webhook payload');
  }
  final payload = decoded.map((key, value) => MapEntry(key.toString(), value));
  return ThirdwebWebhook(
    payload: payload,
    digest: sha256.convert(utf8.encode(rawBody)).toString(),
  );
}

void _verifyHmac({
  required String rawBody,
  required String secret,
  required String? signature,
  required String? timestampRaw,
  required int? timestamp,
  required DateTime? now,
  required Duration tolerance,
}) {
  if (signature == null || timestampRaw == null || timestamp == null) {
    throw const FormatException('Missing Thirdweb webhook authentication');
  }
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(signature)) {
    throw const FormatException('Invalid Thirdweb webhook signature');
  }

  final currentSeconds =
      (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
  if ((currentSeconds - timestamp).abs() > tolerance.inSeconds) {
    throw const FormatException('Expired Thirdweb webhook');
  }

  final signed = utf8.encode('$timestampRaw.$rawBody');
  final expected = Hmac(sha256, utf8.encode(secret)).convert(signed).bytes;
  final received = _decodeHex(signature);
  if (!_constantTimeEquals(expected, received)) {
    throw const FormatException('Invalid Thirdweb webhook signature');
  }
}

void _verifyBearerToken(String? authorization, String secret) {
  final parts = authorization?.trim().split(RegExp(r'\s+')) ?? const <String>[];
  if (parts.length != 2 || parts.first.toLowerCase() != 'bearer') {
    throw const FormatException('Missing Thirdweb webhook authentication');
  }
  if (!_constantTimeEquals(utf8.encode(parts.last), utf8.encode(secret))) {
    throw const FormatException('Invalid Thirdweb webhook authorization');
  }
}

List<int> _decodeHex(String value) {
  final bytes = <int>[];
  for (var index = 0; index < value.length; index += 2) {
    bytes.add(int.parse(value.substring(index, index + 2), radix: 16));
  }
  return bytes;
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
