import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Handles Email OTP Authentication via local SMTP server.
class OtpService {
  static final OtpService _instance = OtpService._internal();
  factory OtpService() => _instance;
  OtpService._internal();

  String? _currentOtp;

  /// Generates an OTP locally and sends it to the [email] via local backend.
  Future<void> sendEmailOtp({
    required String email,
    required VoidCallback onCodeSent,
    required Function(String) onError,
  }) async {
    try {
      // Generate random 6 digit code
      _currentOtp = (Random().nextInt(900000) + 100000).toString();
      
      // Make HTTP request to our local email_server.dart
      final response = await http.post(
        Uri.parse('http://localhost:3000'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': _currentOtp,
        }),
      );

      if (response.statusCode == 200) {
        onCodeSent();
      } else {
        final err = jsonDecode(response.body)['error'] ?? 'Unknown error';
        onError('Server error: \$err');
      }
    } catch (e) {
      debugPrint("HTTP Error: \$e");
      onError('Failed to connect to email server. Is email_server.dart running?');
    }
  }

  /// Verifies the OTP [code] entered by the user.
  Future<bool> verifyOtp(String code) async {
    return _currentOtp != null && code == _currentOtp;
  }
}
