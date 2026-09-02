import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ThirdwebDonationPayment {
  final String id;
  final Uri link;

  const ThirdwebDonationPayment({required this.id, required this.link});
}

class WalletDonationTransfer {
  final int chainId;
  final String tokenAddress;
  final String recipient;
  final BigInt amount;

  const WalletDonationTransfer({
    required this.chainId,
    required this.tokenAddress,
    required this.recipient,
    required this.amount,
  });
}

class ThirdwebDonationService {
  const ThirdwebDonationService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<ThirdwebDonationPayment> createDonationPayment({
    required BigInt amountUsdcSmallestUnit,
    required String accessToken,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) {
      throw StateError('Your XMO session is unavailable. Sign in again.');
    }
    final client = _client ?? http.Client();
    try {
      final response = await client.post(
        _endpoint(),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'amountUsdcSmallestUnit': amountUsdcSmallestUnit.toString(),
        }),
      );

      final decoded = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_errorMessage(decoded));
      }

      final payment = decoded['payment'];
      if (payment is! Map<String, dynamic>) {
        throw Exception('Donation server did not return payment details.');
      }

      final id = payment['id']?.toString();
      final linkRaw = payment['link']?.toString();
      final link = linkRaw == null ? null : Uri.tryParse(linkRaw);
      if (id == null || id.isEmpty || !_isSafeCheckoutLink(link)) {
        throw Exception('Donation server did not return a checkout link.');
      }

      return ThirdwebDonationPayment(id: id, link: link!);
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<WalletDonationTransfer> createWalletDonationTransfer({
    required BigInt amountUsdcSmallestUnit,
    required String accessToken,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) {
      throw StateError('Your XMO session is unavailable. Sign in again.');
    }
    final client = _client ?? http.Client();
    try {
      final response = await client.post(
        _endpoint(),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'amountUsdcSmallestUnit': amountUsdcSmallestUnit.toString(),
          'checkoutMode': 'wallet',
        }),
      );

      final decoded = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_errorMessage(decoded));
      }

      final transfer = decoded['transfer'];
      if (transfer is! Map<String, dynamic>) {
        throw Exception('Donation server did not return transfer details.');
      }
      final chainId = int.tryParse(transfer['chainId']?.toString() ?? '');
      final tokenAddress = transfer['tokenAddress']?.toString() ?? '';
      final recipient = transfer['recipient']?.toString() ?? '';
      final amount = BigInt.tryParse(transfer['amount']?.toString() ?? '');
      if (chainId != 8453 ||
          !_isEthereumAddress(tokenAddress) ||
          !_isEthereumAddress(recipient) ||
          amount == null ||
          amount != amountUsdcSmallestUnit) {
        throw Exception('Donation server returned invalid transfer details.');
      }

      return WalletDonationTransfer(
        chainId: chainId!,
        tokenAddress: tokenAddress,
        recipient: recipient,
        amount: amount,
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  Uri _endpoint() {
    final configured = AppConfig.donationServerUrl.trim();
    if (configured.isNotEmpty) {
      final normalized = configured.endsWith('/')
          ? configured.substring(0, configured.length - 1)
          : configured;
      if (normalized.endsWith('/create')) {
        return Uri.parse(normalized);
      }
      return Uri.parse('$normalized/create');
    }

    final otpValue = AppConfig.otpServerUrl.trim();
    final normalized = otpValue.endsWith('/')
        ? otpValue.substring(0, otpValue.length - 1)
        : otpValue;
    return Uri.parse('$normalized/donations/create');
  }

  Map<String, dynamic> _decodeJson(String body) {
    if (body.trim().isEmpty) return const {};
    final value = jsonDecode(body);
    if (value is Map<String, dynamic>) return value;
    return const {};
  }

  String _errorMessage(Map<String, dynamic> body) {
    final message = _findMessage(body);
    return message ?? 'Unable to create donation checkout link.';
  }

  String? _findMessage(Map<String, dynamic> body) {
    final direct = body['message'] ?? body['error'];
    if (direct != null) return direct.toString();

    final result = body['result'];
    if (result is Map<String, dynamic>) {
      final nested = result['message'] ?? result['error'];
      if (nested != null) return nested.toString();
    }
    return null;
  }

  bool _isSafeCheckoutLink(Uri? link) =>
      link != null &&
      link.isAbsolute &&
      link.scheme == 'https' &&
      link.host.isNotEmpty &&
      link.userInfo.isEmpty;

  bool _isEthereumAddress(String value) =>
      RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);
}
