part of xmo_auth_server;

const _donationPlanTtl = Duration(minutes: 5);
const _thirdwebWebhookBodyLimit = 256 * 1024;

Future<void> _createDonationPayment(HttpRequest request) async {
  final principal = _matrixRequestPrincipals[request];
  if (principal == null) {
    await _json(request, HttpStatus.unauthorized, {
      'error': 'Valid XMO session required',
    });
    return;
  }
  final body = await _readJson(request);
  final amount = _parseDonationAmount(body['amountUsdcSmallestUnit']);
  final mode = body['checkoutMode']?.toString().trim().toLowerCase();
  if (amount == null || amount < BigInt.from(5000000)) {
    await _json(request, HttpStatus.badRequest, {
      'error': 'Minimum donation is \$5',
    });
    return;
  }
  if (mode != null && mode.isNotEmpty && mode != 'hosted' && mode != 'native') {
    await _json(request, HttpStatus.badRequest, {
      'error': 'Invalid donation checkout mode',
    });
    return;
  }
  if (!_thirdwebGateway.isConfigured ||
      !_isDonationAddress(_donationRecipientAddress)) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Donation checkout is not configured',
    });
    return;
  }
  if (mode == 'native') {
    await _createNativeDonation(request, principal.userId, body, amount);
    return;
  }
  try {
    final payment = await _thirdwebGateway.createPaymentLink(
      amount: amount,
      recipient: _donationRecipientAddress,
      purchaseData: const {'source': 'xmo_app'},
    );
    await _json(request, HttpStatus.ok, {
      'success': true,
      'payment': {'id': payment.id, 'link': payment.link.toString()},
    });
  } catch (error, stackTrace) {
    _logger.error('thirdweb_payment_creation_failed', error, stackTrace);
    await _json(request, HttpStatus.badGateway, {
      'error':
          'Donation checkout is temporarily unavailable. Please try again.',
    });
  }
}

Future<void> _createNativeDonation(
  HttpRequest request,
  String matrixUserId,
  Map<String, dynamic> body,
  BigInt amount,
) async {
  final walletAddress = body['walletAddress']?.toString().trim() ?? '';
  if (!_isDonationAddress(walletAddress)) {
    await _json(request, HttpStatus.badRequest, {
      'error': 'Connect a valid wallet before starting payment',
    });
    return;
  }
  if (!_donationStoreReady || !_thirdwebWebhookConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'In-app donation checkout is temporarily unavailable',
    });
    return;
  }
  final donationId = _randomDonationId();
  final purchaseData = <String, Object?>{
    'source': 'xmo_app',
    'donationId': donationId,
  };
  try {
    final link = await _thirdwebGateway.createPaymentLink(
      amount: amount,
      recipient: _donationRecipientAddress,
      purchaseData: purchaseData,
    );
    final prepared = await _thirdwebGateway.prepareBaseUsdcPayment(
      paymentLinkId: link.id,
      amount: amount,
      sender: walletAddress,
      receiver: _donationRecipientAddress,
      purchaseData: purchaseData,
    );
    final now = DateTime.now().toUtc();
    final maximumExpiration = now.add(_donationPlanTtl);
    final expiresAt = prepared.expiresAt.isBefore(maximumExpiration)
        ? prepared.expiresAt
        : maximumExpiration;
    final plan = <String, dynamic>{
      ...prepared.toJson(),
      'chainId': thirdwebBaseChainId,
      'tokenAddress': thirdwebBaseUsdcAddress,
      'recipient': _donationRecipientAddress,
      'amount': amount.toString(),
      'expiresAt': expiresAt.toIso8601String(),
    };
    await _donationStore.create(
      DonationRecord(
        donationId: donationId,
        thirdwebPaymentId: link.id,
        matrixUserId: matrixUserId,
        walletAddress: walletAddress.toLowerCase(),
        destinationChainId: thirdwebBaseChainId,
        destinationTokenAddress: thirdwebBaseUsdcAddress.toLowerCase(),
        recipientAddress: _donationRecipientAddress.toLowerCase(),
        destinationAmount: amount,
        plan: plan,
        status: 'awaiting_signature',
        createdAt: now,
        expiresAt: expiresAt,
        updatedAt: now,
      ),
    );
    await _json(request, HttpStatus.ok, {
      'success': true,
      'donation': {'id': donationId, 'status': 'awaiting_signature', ...plan},
    });
  } catch (error, stackTrace) {
    _logger.error('thirdweb_native_payment_creation_failed', error, stackTrace);
    await _json(request, HttpStatus.badGateway, {
      'error':
          'In-app donation checkout is temporarily unavailable. Try browser checkout.',
    });
  }
}

Future<void> _submitDonationTransaction(HttpRequest request) async {
  final principal = _matrixRequestPrincipals[request];
  if (principal == null || !_donationStoreReady) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Donation tracking is temporarily unavailable',
    });
    return;
  }
  final body = await _readJson(request);
  final donationId = body['donationId']?.toString().trim() ?? '';
  final transactionId = body['transactionId']?.toString().trim() ?? '';
  final transactionHash = body['transactionHash']?.toString().trim() ?? '';
  final action = body['action']?.toString().trim().toLowerCase() ?? '';
  final chainId = int.tryParse(body['chainId']?.toString() ?? '');
  if (!_isDonationId(donationId) ||
      transactionId.isEmpty ||
      !_isDonationTransactionHash(transactionHash) ||
      action.isEmpty ||
      chainId != thirdwebBaseChainId) {
    await _json(request, HttpStatus.badRequest, {
      'error': 'Invalid donation transaction',
    });
    return;
  }
  final donation = await _donationStore.findOwned(
    donationId: donationId,
    matrixUserId: principal.userId,
  );
  if (donation == null) {
    await _json(request, HttpStatus.notFound, {'error': 'Donation not found'});
    return;
  }
  if (donation.isExpired && donation.status == 'awaiting_signature') {
    await _donationStore.updateStatus(
      donationId: donationId,
      status: 'expired',
    );
    await _json(request, HttpStatus.gone, {'error': 'Donation quote expired'});
    return;
  }
  final accepted = await _donationStore.recordSubmission(
    donation: donation,
    transactionId: transactionId,
    transactionHash: transactionHash.toLowerCase(),
    action: action,
    chainId: chainId!,
  );
  if (!accepted) {
    await _json(request, HttpStatus.conflict, {
      'error': 'Transaction does not match this donation',
    });
    return;
  }
  await _json(request, HttpStatus.ok, {'success': true, 'status': 'submitted'});
}

Future<void> _getDonationStatus(HttpRequest request) async {
  final principal = _matrixRequestPrincipals[request];
  if (principal == null || !_donationStoreReady) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Donation tracking is temporarily unavailable',
    });
    return;
  }
  final donationId = request.uri.queryParameters['id']?.trim() ?? '';
  if (!_isDonationId(donationId)) {
    await _json(request, HttpStatus.badRequest, {
      'error': 'Invalid donation id',
    });
    return;
  }
  final donation = await _donationStore.findOwned(
    donationId: donationId,
    matrixUserId: principal.userId,
  );
  if (donation == null) {
    await _json(request, HttpStatus.notFound, {'error': 'Donation not found'});
    return;
  }
  final status = await _refreshDonationStatus(donation);
  await _json(request, HttpStatus.ok, {
    'success': true,
    'donation': {'id': donationId, 'status': status},
  });
}

Future<void> _handleThirdwebDonationWebhook(HttpRequest request) async {
  if (!_donationStoreReady || !_thirdwebWebhookConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'error': 'Webhook is not configured',
    });
    return;
  }
  try {
    final rawBody = await _readBoundedText(request, _thirdwebWebhookBodyLimit);
    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      if (values.isNotEmpty) headers[name.toLowerCase()] = values.first;
    });
    final webhook = verifyThirdwebWebhook(
      rawBody: rawBody,
      headers: headers,
      secret: _thirdwebWebhookSecret,
    );
    if (!await _donationStore.claimWebhookEvent(webhook.digest)) {
      await _json(request, HttpStatus.ok, {'success': true});
      return;
    }
    try {
      final donationId = _findNestedString(webhook.payload, 'donationId');
      if (donationId != null && _isDonationId(donationId)) {
        final donation = await _donationStore.findById(donationId);
        if (donation != null) {
          final transactionHash = _findNestedString(
            webhook.payload,
            'transactionHash',
          );
          if (transactionHash != null &&
              _isDonationTransactionHash(transactionHash)) {
            await _refreshDonationStatusForTransaction(
              donation,
              transactionHash.toLowerCase(),
            );
          } else {
            await _refreshDonationStatus(donation);
          }
        }
      }
    } catch (_) {
      await _donationStore.releaseWebhookEvent(webhook.digest);
      rethrow;
    }
    await _json(request, HttpStatus.ok, {'success': true});
  } on FormatException {
    await _json(request, HttpStatus.unauthorized, {'error': 'Invalid webhook'});
  } catch (error, stackTrace) {
    _logger.error('thirdweb_webhook_processing_failed', error, stackTrace);
    await _json(request, HttpStatus.internalServerError, {
      'error': 'Webhook processing failed',
    });
  }
}

Future<String> _refreshDonationStatus(DonationRecord donation) async {
  if (const {'confirmed', 'failed', 'expired'}.contains(donation.status)) {
    return donation.status;
  }
  if (donation.isExpired && donation.status == 'awaiting_signature') {
    await _donationStore.updateStatus(
      donationId: donation.donationId,
      status: 'expired',
    );
    return 'expired';
  }
  final transaction = await _donationStore.settlementTransaction(
    donation.donationId,
  );
  if (transaction == null) return donation.status;
  return _refreshDonationStatusForTransaction(
    donation,
    transaction.transactionHash,
    transactionId: transaction.transactionId,
  );
}

Future<String> _refreshDonationStatusForTransaction(
  DonationRecord donation,
  String transactionHash, {
  String? transactionId,
}) async {
  final provider = await _thirdwebGateway.paymentStatus(
    chainId: thirdwebBaseChainId,
    transactionHash: transactionHash,
    transactionId: transactionId,
  );
  if (!_statusMatchesDonation(provider, donation)) {
    logWarning('thirdweb_donation_status_mismatch', {
      'donationId': donation.donationId,
    });
    return donation.status;
  }
  final status = switch (provider.status) {
    'COMPLETED' => 'confirmed',
    'FAILED' => 'failed',
    _ => 'submitted',
  };
  await _donationStore.updateStatus(
    donationId: donation.donationId,
    status: status,
  );
  return status;
}

bool _statusMatchesDonation(
  ThirdwebPaymentStatus provider,
  DonationRecord donation,
) {
  final purchaseData = provider.purchaseData;
  final identityMatches =
      provider.paymentId == donation.thirdwebPaymentId &&
      purchaseData?['donationId']?.toString() == donation.donationId;
  if (!identityMatches) return false;
  if (provider.status == 'FAILED') return true;
  return provider.status == 'COMPLETED' &&
      provider.sender?.toLowerCase() == donation.walletAddress &&
      provider.receiver?.toLowerCase() == donation.recipientAddress &&
      provider.destinationChainId == donation.destinationChainId &&
      provider.destinationTokenAddress?.toLowerCase() ==
          donation.destinationTokenAddress &&
      provider.destinationAmount == donation.destinationAmount;
}

Future<String> _readBoundedText(HttpRequest request, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    if (builder.length + chunk.length > maxBytes) {
      throw const FormatException('Request body is too large');
    }
    builder.add(chunk);
  }
  return utf8.decode(builder.takeBytes());
}

String? _findNestedString(Object? value, String key) {
  if (value is Map) {
    final direct = value[key];
    if (direct != null) return direct.toString();
    for (final nested in value.values) {
      final found = _findNestedString(nested, key);
      if (found != null) return found;
    }
  } else if (value is List) {
    for (final nested in value) {
      final found = _findNestedString(nested, key);
      if (found != null) return found;
    }
  }
  return null;
}

BigInt? _parseDonationAmount(Object? value) =>
    BigInt.tryParse(value?.toString().trim() ?? '');

String _randomDonationId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

bool _isDonationId(String value) => RegExp(r'^[0-9a-f]{32}$').hasMatch(value);
bool _isDonationAddress(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);
bool _isDonationTransactionHash(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(value);
