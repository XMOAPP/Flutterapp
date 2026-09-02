import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const thirdwebBaseChainId = 8453;
const thirdwebBaseUsdcAddress = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';

class ThirdwebPaymentGateway {
  ThirdwebPaymentGateway({
    required this.secretKey,
    http.Client? client,
    Uri? apiBaseUri,
    Uri? bridgeBaseUri,
  }) : _client = client,
       apiBaseUri = apiBaseUri ?? Uri.parse('https://api.thirdweb.com'),
       bridgeBaseUri =
           bridgeBaseUri ?? Uri.parse('https://bridge.thirdweb.com');

  final String secretKey;
  final http.Client? _client;
  final Uri apiBaseUri;
  final Uri bridgeBaseUri;

  bool get isConfigured => secretKey.trim().isNotEmpty;

  Future<ThirdwebPaymentLink> createPaymentLink({
    required BigInt amount,
    required String recipient,
    required Map<String, Object?> purchaseData,
  }) async {
    final response = await _post(apiBaseUri.resolve('/v1/bridge/payments'), {
      'name': 'XMO Donation',
      'description': 'Support XMO development',
      'token': {
        'address': thirdwebBaseUsdcAddress,
        'chainId': thirdwebBaseChainId,
        'amount': amount.toString(),
      },
      'recipient': recipient,
      'purchaseData': purchaseData,
    });
    final result = _map(response['result']);
    final id = result?['id']?.toString().trim() ?? '';
    final link = Uri.tryParse(result?['link']?.toString() ?? '');
    if (id.isEmpty || link == null || !_isHttpsUri(link)) {
      throw const ThirdwebGatewayException(
        'Thirdweb did not return valid payment details',
      );
    }
    return ThirdwebPaymentLink(id: id, link: link);
  }

  Future<ThirdwebPreparedPayment> prepareBaseUsdcPayment({
    required String paymentLinkId,
    required BigInt amount,
    required String sender,
    required String receiver,
    required Map<String, Object?> purchaseData,
  }) async {
    if (!_isEthereumAddress(sender) || !_isEthereumAddress(receiver)) {
      throw const ThirdwebGatewayException('Invalid payment wallet address');
    }
    final response = await _post(bridgeBaseUri.resolve('/v1/buy/prepare'), {
      'amount': amount.toString(),
      'buyAmountWei': amount.toString(),
      'originChainId': thirdwebBaseChainId.toString(),
      'originTokenAddress': thirdwebBaseUsdcAddress,
      'destinationChainId': thirdwebBaseChainId.toString(),
      'destinationTokenAddress': thirdwebBaseUsdcAddress,
      'sender': sender,
      'receiver': receiver,
      'paymentLinkId': paymentLinkId,
      'purchaseData': purchaseData,
      'maxSteps': 1,
    });
    final data = _map(response['data']);
    if (data == null) {
      throw const ThirdwebGatewayException(
        'Thirdweb did not return a prepared payment',
      );
    }

    final destinationAmount = _bigInt(data['destinationAmount']);
    final originAmount = _bigInt(data['originAmount']);
    if (destinationAmount != amount ||
        originAmount == null ||
        originAmount <= BigInt.zero) {
      throw const ThirdwebGatewayException(
        'Thirdweb returned inconsistent payment amounts',
      );
    }

    final transactions = <ThirdwebPreparedTransaction>[];
    final steps = data['steps'];
    if (steps is List) {
      for (final rawStep in steps) {
        final step = _map(rawStep);
        final rawTransactions = step?['transactions'];
        if (rawTransactions is! List) continue;
        for (final rawTransaction in rawTransactions) {
          transactions.add(
            ThirdwebPreparedTransaction.fromJson(
              _map(rawTransaction) ?? const {},
            ),
          );
        }
      }
    }
    if (transactions.isEmpty || transactions.length > 4) {
      throw const ThirdwebGatewayException(
        'Thirdweb returned an unsupported payment route',
      );
    }
    if (!transactions.any((transaction) => !transaction.isApproval)) {
      throw const ThirdwebGatewayException(
        'Thirdweb payment route has no settlement transaction',
      );
    }

    final timestamp =
        _epochDateTime(data['timestamp']) ?? DateTime.now().toUtc();
    final providerExpiration = _epochDateTime(data['expiration']);
    final maximumExpiration = DateTime.now().toUtc().add(
      const Duration(minutes: 5),
    );
    final expiration =
        providerExpiration != null &&
            providerExpiration.isBefore(maximumExpiration)
        ? providerExpiration
        : maximumExpiration;

    return ThirdwebPreparedPayment(
      paymentLinkId: paymentLinkId,
      originAmount: originAmount,
      destinationAmount: destinationAmount!,
      timestamp: timestamp,
      expiresAt: expiration,
      transactions: transactions,
    );
  }

  Future<ThirdwebPaymentStatus> paymentStatus({
    required int chainId,
    required String transactionHash,
    String? transactionId,
  }) async {
    if (chainId != thirdwebBaseChainId ||
        !_isTransactionHash(transactionHash)) {
      throw const ThirdwebGatewayException('Invalid payment status request');
    }
    final query = <String, String>{
      'chainId': chainId.toString(),
      'transactionHash': transactionHash,
    };
    if (transactionId != null && transactionId.trim().isNotEmpty) {
      query['transactionId'] = transactionId.trim();
    }
    final uri = bridgeBaseUri
        .resolve('/v1/status')
        .replace(queryParameters: query);
    final response = await _get(uri);
    final data = _map(response['data']);
    if (data == null) {
      throw const ThirdwebGatewayException(
        'Thirdweb did not return payment status',
      );
    }
    return ThirdwebPaymentStatus.fromJson(data);
  }

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, Object?> body) async {
    return _withClient((client) async {
      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-secret-key': secretKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      return _decodeResponse(response);
    });
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    return _withClient((client) async {
      final response = await client
          .get(uri, headers: {'x-secret-key': secretKey})
          .timeout(const Duration(seconds: 15));
      return _decodeResponse(response);
    });
  }

  Future<T> _withClient<T>(
    Future<T> Function(http.Client client) operation,
  ) async {
    final client = _client ?? http.Client();
    try {
      return await operation(client);
    } finally {
      if (_client == null) client.close();
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      decoded = _map(jsonDecode(response.body)) ?? <String, dynamic>{};
    } on FormatException {
      decoded = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['message'] ?? decoded['error'];
      throw ThirdwebGatewayException(
        message?.toString() ?? 'Thirdweb request failed',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}

class ThirdwebPaymentLink {
  const ThirdwebPaymentLink({required this.id, required this.link});

  final String id;
  final Uri link;
}

class ThirdwebPreparedPayment {
  const ThirdwebPreparedPayment({
    required this.paymentLinkId,
    required this.originAmount,
    required this.destinationAmount,
    required this.timestamp,
    required this.expiresAt,
    required this.transactions,
  });

  final String paymentLinkId;
  final BigInt originAmount;
  final BigInt destinationAmount;
  final DateTime timestamp;
  final DateTime expiresAt;
  final List<ThirdwebPreparedTransaction> transactions;

  Map<String, Object?> toJson() => {
    'paymentId': paymentLinkId,
    'originAmount': originAmount.toString(),
    'destinationAmount': destinationAmount.toString(),
    'timestamp': timestamp.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'transactions': transactions.map((value) => value.toJson()).toList(),
  };
}

class ThirdwebPreparedTransaction {
  const ThirdwebPreparedTransaction({
    required this.id,
    required this.action,
    required this.chainId,
    required this.to,
    required this.data,
    required this.value,
  });

  factory ThirdwebPreparedTransaction.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final action = json['action']?.toString().trim().toLowerCase() ?? '';
    final chainId = int.tryParse(json['chainId']?.toString() ?? '');
    final to = json['to']?.toString().trim() ?? '';
    final data = json['data']?.toString().trim() ?? '';
    final value = _bigInt(json['value']) ?? BigInt.zero;
    if (id.isEmpty ||
        !const {
          'approval',
          'transfer',
          'buy',
          'sell',
          'transaction',
        }.contains(action) ||
        chainId != thirdwebBaseChainId ||
        !_isEthereumAddress(to) ||
        !_isHexData(data) ||
        data.length > 131074 ||
        value < BigInt.zero) {
      throw const ThirdwebGatewayException(
        'Thirdweb returned an invalid transaction step',
      );
    }
    return ThirdwebPreparedTransaction(
      id: id,
      action: action,
      chainId: chainId!,
      to: to,
      data: data,
      value: value,
    );
  }

  final String id;
  final String action;
  final int chainId;
  final String to;
  final String data;
  final BigInt value;

  bool get isApproval => action == 'approval';

  Map<String, Object?> toJson() => {
    'id': id,
    'action': action,
    'chainId': chainId,
    'to': to,
    'data': data,
    'value': value.toString(),
  };
}

class ThirdwebPaymentStatus {
  const ThirdwebPaymentStatus({
    required this.status,
    required this.paymentId,
    required this.sender,
    required this.receiver,
    required this.destinationChainId,
    required this.destinationTokenAddress,
    required this.destinationAmount,
    required this.purchaseData,
  });

  factory ThirdwebPaymentStatus.fromJson(Map<String, dynamic> json) {
    return ThirdwebPaymentStatus(
      status: json['status']?.toString().trim().toUpperCase() ?? 'NOT_FOUND',
      paymentId: json['paymentId']?.toString().trim(),
      sender: json['sender']?.toString().trim(),
      receiver: json['receiver']?.toString().trim(),
      destinationChainId: int.tryParse(
        json['destinationChainId']?.toString() ?? '',
      ),
      destinationTokenAddress: json['destinationTokenAddress']
          ?.toString()
          .trim(),
      destinationAmount: _bigInt(json['destinationAmount']),
      purchaseData: _map(json['purchaseData']),
    );
  }

  final String status;
  final String? paymentId;
  final String? sender;
  final String? receiver;
  final int? destinationChainId;
  final String? destinationTokenAddress;
  final BigInt? destinationAmount;
  final Map<String, dynamic>? purchaseData;
}

class ThirdwebGatewayException implements Exception {
  const ThirdwebGatewayException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

BigInt? _bigInt(Object? value) {
  if (value == null) return null;
  return BigInt.tryParse(value.toString());
}

DateTime? _epochDateTime(Object? value) {
  final raw = int.tryParse(value?.toString() ?? '');
  if (raw == null) return null;
  final milliseconds = raw < 100000000000 ? raw * 1000 : raw;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

bool _isHttpsUri(Uri uri) =>
    uri.isAbsolute && uri.scheme == 'https' && uri.host.isNotEmpty;

bool _isEthereumAddress(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);

bool _isTransactionHash(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(value);

bool _isHexData(String value) =>
    RegExp(r'^0x(?:[0-9a-fA-F]{2})*$').hasMatch(value);
