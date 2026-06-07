import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ThirdwebDonationPayment {
  final String id;
  final Uri link;

  const ThirdwebDonationPayment({
    required this.id,
    required this.link,
  });
}

class ThirdwebDonationService {
  const ThirdwebDonationService();

  Future<ThirdwebDonationPayment> createDonationPayment({
    required BigInt amountUsdcSmallestUnit,
    required String donorUserId,
    String? donorDisplayName,
  }) async {
    final response = await http.post(
      _endpoint(),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'amountUsdcSmallestUnit': amountUsdcSmallestUnit.toString(),
        'donorUserId': donorUserId,
        if (donorDisplayName != null && donorDisplayName.trim().isNotEmpty)
          'donorDisplayName': donorDisplayName.trim(),
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
    if (id == null || id.isEmpty || link == null) {
      throw Exception('Donation server did not return a checkout link.');
    }

    return ThirdwebDonationPayment(id: id, link: link);
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
}
