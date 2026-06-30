part of xmo_auth_server;

Future<void> _createDonationPayment(HttpRequest request) async {
  final body = await _readJson(request);
  final amount = _parseAmount(body['amountUsdcSmallestUnit']);
  final donorUserId = body['donorUserId']?.toString().trim() ?? '';
  final donorDisplayName = body['donorDisplayName']?.toString().trim() ?? '';

  if (_thirdwebSecretKey.isEmpty) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Thirdweb secret key is not configured'},
    );
    return;
  }

  if (_donationRecipientAddress.isEmpty) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Donation recipient wallet is not configured'},
    );
    return;
  }

  if (amount == null || amount <= BigInt.zero) {
    await _json(
      request,
      HttpStatus.badRequest,
      {'error': 'Invalid donation amount'},
    );
    return;
  }

  final minSmallestUnit = BigInt.from((_minDonationUsd * 1000000).round());
  if (amount < minSmallestUnit) {
    await _json(
      request,
      HttpStatus.badRequest,
      {'error': 'Minimum donation is \$5'},
    );
    return;
  }

  final response = await _postThirdwebPayment(
    amountUsdcSmallestUnit: amount,
    donorUserId: donorUserId,
    donorDisplayName: donorDisplayName,
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    await _json(
      request,
      response.statusCode,
      {'error': _thirdwebErrorMessage(response.body)},
    );
    return;
  }

  final decoded = _decodeJsonMap(response.body);
  final result = decoded['result'];
  if (result is! Map<String, dynamic>) {
    await _json(
      request,
      HttpStatus.badGateway,
      {'error': 'Thirdweb did not return payment details'},
    );
    return;
  }

  final id = result['id']?.toString() ?? '';
  final link = result['link']?.toString() ?? '';
  if (id.isEmpty || Uri.tryParse(link) == null) {
    await _json(
      request,
      HttpStatus.badGateway,
      {'error': 'Thirdweb did not return a checkout link'},
    );
    return;
  }

  await _json(request, HttpStatus.ok, {
    'success': true,
    'payment': {
      'id': id,
      'link': link,
    },
  });
}

Future<_ThirdwebResponse> _postThirdwebPayment({
  required BigInt amountUsdcSmallestUnit,
  required String donorUserId,
  required String donorDisplayName,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('$_thirdwebBaseUrl/v1/bridge/payments'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.add('x-secret-key', _thirdwebSecretKey);
    request.write(jsonEncode({
      'name': 'XMO Donation',
      'description': 'Support XMO development',
      'token': {
        'address': _baseUsdcAddress,
        'chainId': _baseChainId,
        'amount': amountUsdcSmallestUnit.toString(),
      },
      'recipient': _donationRecipientAddress,
      'purchaseData': {
        'source': 'xmo_app',
        if (donorUserId.isNotEmpty) 'donorUserId': donorUserId,
        if (donorDisplayName.isNotEmpty) 'donorDisplayName': donorDisplayName,
      },
    }));

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return _ThirdwebResponse(
      statusCode: response.statusCode,
      body: body,
    );
  } finally {
    client.close(force: true);
  }
}

BigInt? _parseAmount(Object? value) {
  if (value == null) return null;
  return BigInt.tryParse(value.toString().trim());
}

String _thirdwebErrorMessage(String body) {
  try {
    final decoded = _decodeJsonMap(body);
    final direct = decoded['message'] ?? decoded['error'];
    if (direct != null) return direct.toString();

    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      final nested = result['message'] ?? result['error'];
      if (nested != null) return nested.toString();
    }
  } catch (_) {
    // Fall through to a generic message.
  }
  return 'Unable to create donation checkout link';
}

class _ThirdwebResponse {
  final int statusCode;
  final String body;

  const _ThirdwebResponse({
    required this.statusCode,
    required this.body,
  });
}
