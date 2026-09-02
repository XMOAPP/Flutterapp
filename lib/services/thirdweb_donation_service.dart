import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

const _baseChainId = 8453;
const _baseUsdcAddress = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';

class ThirdwebDonationPayment {
  const ThirdwebDonationPayment({required this.id, required this.link});
  final String id;
  final Uri link;
}

class ThirdwebNativeTransaction {
  const ThirdwebNativeTransaction({
    required this.id,
    required this.action,
    required this.chainId,
    required this.to,
    required this.data,
    required this.value,
  });

  final String id;
  final String action;
  final int chainId;
  final String to;
  final String data;
  final BigInt value;
}

class ThirdwebNativeDonation {
  const ThirdwebNativeDonation({
    required this.id,
    required this.paymentId,
    required this.chainId,
    required this.tokenAddress,
    required this.recipient,
    required this.amount,
    required this.originAmount,
    required this.expiresAt,
    required this.transactions,
  });

  final String id;
  final String paymentId;
  final int chainId;
  final String tokenAddress;
  final String recipient;
  final BigInt amount;
  final BigInt originAmount;
  final DateTime expiresAt;
  final List<ThirdwebNativeTransaction> transactions;
}

class ThirdwebDonationService {
  const ThirdwebDonationService({http.Client? client}) : _client = client;
  final http.Client? _client;

  Future<ThirdwebDonationPayment> createDonationPayment({
    required BigInt amountUsdcSmallestUnit,
    required String accessToken,
  }) async {
    final decoded = await _post(_endpoint('create'), accessToken, {
      'amountUsdcSmallestUnit': amountUsdcSmallestUnit.toString(),
    });
    final payment = _map(decoded['payment']);
    final id = payment?['id']?.toString().trim() ?? '';
    final link = Uri.tryParse(payment?['link']?.toString() ?? '');
    if (id.isEmpty || !_isSafeCheckoutLink(link)) {
      throw Exception('Donation server did not return a checkout link.');
    }
    return ThirdwebDonationPayment(id: id, link: link!);
  }

  Future<ThirdwebNativeDonation> createNativeDonationPayment({
    required BigInt amountUsdcSmallestUnit,
    required String accessToken,
    required String walletAddress,
  }) async {
    if (!_isEthereumAddress(walletAddress)) {
      throw StateError('Reconnect your wallet and try again.');
    }
    final decoded = await _post(_endpoint('create'), accessToken, {
      'amountUsdcSmallestUnit': amountUsdcSmallestUnit.toString(),
      'checkoutMode': 'native',
      'walletAddress': walletAddress,
    });
    final donation = _map(decoded['donation']);
    if (donation == null) {
      throw Exception('Donation server did not return payment details.');
    }
    final id = donation['id']?.toString().trim() ?? '';
    final paymentId = donation['paymentId']?.toString().trim() ?? '';
    final chainId = int.tryParse(donation['chainId']?.toString() ?? '');
    final tokenAddress = donation['tokenAddress']?.toString().trim() ?? '';
    final recipient = donation['recipient']?.toString().trim() ?? '';
    final amount = BigInt.tryParse(donation['amount']?.toString() ?? '');
    final originAmount = BigInt.tryParse(
      donation['originAmount']?.toString() ?? '',
    );
    final expiresAt = DateTime.tryParse(
      donation['expiresAt']?.toString() ?? '',
    )?.toUtc();
    final transactions = _parseTransactions(donation['transactions']);
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        paymentId.isEmpty ||
        chainId != _baseChainId ||
        tokenAddress.toLowerCase() != _baseUsdcAddress.toLowerCase() ||
        !_isEthereumAddress(recipient) ||
        amount != amountUsdcSmallestUnit ||
        originAmount == null ||
        originAmount <= BigInt.zero ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().toUtc()) ||
        transactions.isEmpty ||
        transactions.length > 4 ||
        !transactions.any((transaction) => transaction.action != 'approval')) {
      throw Exception('Donation server returned an invalid payment plan.');
    }
    return ThirdwebNativeDonation(
      id: id,
      paymentId: paymentId,
      chainId: chainId!,
      tokenAddress: tokenAddress,
      recipient: recipient,
      amount: amount!,
      originAmount: originAmount,
      expiresAt: expiresAt,
      transactions: transactions,
    );
  }

  Future<void> submitNativeTransaction({
    required String donationId,
    required ThirdwebNativeTransaction transaction,
    required String transactionHash,
    required String accessToken,
  }) async {
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(transactionHash)) {
      throw Exception('Wallet did not return a valid transaction hash.');
    }
    await _post(_endpoint('native/submit'), accessToken, {
      'donationId': donationId,
      'transactionId': transaction.id,
      'transactionHash': transactionHash,
      'action': transaction.action,
      'chainId': transaction.chainId,
    });
  }

  Future<String> getNativeDonationStatus({
    required String donationId,
    required String accessToken,
  }) async {
    final token = _requireToken(accessToken);
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        _endpoint('native/status').replace(queryParameters: {'id': donationId}),
        headers: {'Authorization': 'Bearer $token'},
      );
      final decoded = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_errorMessage(decoded));
      }
      final status = _map(decoded['donation'])?['status']?.toString() ?? '';
      if (!const {
        'awaiting_signature',
        'submitted',
        'confirmed',
        'failed',
        'expired',
      }.contains(status)) {
        throw Exception('Donation server returned an invalid status.');
      }
      return status;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<Map<String, dynamic>> _post(
    Uri endpoint,
    String accessToken,
    Map<String, Object?> body,
  ) async {
    final token = _requireToken(accessToken);
    final client = _client ?? http.Client();
    try {
      final response = await client.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final decoded = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_errorMessage(decoded));
      }
      return decoded;
    } finally {
      if (_client == null) client.close();
    }
  }

  List<ThirdwebNativeTransaction> _parseTransactions(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) {
          final item = _map(value) ?? const <String, dynamic>{};
          final id = item['id']?.toString().trim() ?? '';
          final action = item['action']?.toString().trim().toLowerCase() ?? '';
          final chainId = int.tryParse(item['chainId']?.toString() ?? '');
          final to = item['to']?.toString().trim() ?? '';
          final data = item['data']?.toString().trim() ?? '';
          final valueAmount = BigInt.tryParse(item['value']?.toString() ?? '');
          if (id.isEmpty ||
              !const {
                'approval',
                'transfer',
                'buy',
                'sell',
                'transaction',
              }.contains(action) ||
              chainId != _baseChainId ||
              !_isEthereumAddress(to) ||
              !RegExp(r'^0x(?:[0-9a-fA-F]{2})*$').hasMatch(data) ||
              data.length > 131074 ||
              valueAmount == null ||
              valueAmount < BigInt.zero) {
            throw Exception('Donation server returned an invalid transaction.');
          }
          return ThirdwebNativeTransaction(
            id: id,
            action: action,
            chainId: chainId!,
            to: to,
            data: data,
            value: valueAmount,
          );
        })
        .toList(growable: false);
  }

  Uri _endpoint(String suffix) {
    final configured = AppConfig.donationServerUrl.trim();
    final Uri createEndpoint;
    if (configured.isNotEmpty) {
      final normalized = configured.endsWith('/')
          ? configured.substring(0, configured.length - 1)
          : configured;
      createEndpoint = Uri.parse(
        normalized.endsWith('/create') ? normalized : '$normalized/create',
      );
    } else {
      final otp = AppConfig.otpServerUrl.trim();
      final normalized = otp.endsWith('/')
          ? otp.substring(0, otp.length - 1)
          : otp;
      createEndpoint = Uri.parse('$normalized/donations/create');
    }
    final basePath = createEndpoint.path.substring(
      0,
      createEndpoint.path.length - 'create'.length,
    );
    return createEndpoint.replace(path: '$basePath$suffix', query: null);
  }

  String _requireToken(String value) {
    final token = value.trim();
    if (token.isEmpty) {
      throw StateError('Your XMO session is unavailable. Sign in again.');
    }
    return token;
  }

  Map<String, dynamic> _decodeJson(String body) {
    if (body.trim().isEmpty) return const {};
    final value = jsonDecode(body);
    return _map(value) ?? const {};
  }

  Map<String, dynamic>? _map(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : null;

  String _errorMessage(Map<String, dynamic> body) =>
      body['message']?.toString() ??
      body['error']?.toString() ??
      'Unable to process donation.';

  bool _isSafeCheckoutLink(Uri? link) =>
      link != null &&
      link.isAbsolute &&
      link.scheme == 'https' &&
      link.host.isNotEmpty &&
      link.userInfo.isEmpty;

  bool _isEthereumAddress(String value) =>
      RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);
}
