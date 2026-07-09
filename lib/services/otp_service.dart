import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Handles Email OTP Authentication via local SMTP server.
class OtpService {
  static final OtpService _instance = OtpService._internal();
  factory OtpService() => _instance;
  OtpService._internal();

  Uri get _otpBaseUri {
    final value = AppConfig.otpServerUrl.trim();
    final normalized =
        value.endsWith('/') ? value.substring(0, value.length - 1) : value;
    return Uri.parse(normalized);
  }

  Uri _endpoint(String path) {
    final base = _otpBaseUri;
    return base.replace(path: '${base.path}/$path');
  }

  /// Requests the backend to generate and send an OTP to [email].
  Future<void> sendEmailOtp({
    required String email,
    required VoidCallback onCodeSent,
    required Function(String) onError,
  }) async {
    try {
      final response = await http.post(
        _endpoint('send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
        }),
      );

      if (response.statusCode == 200) {
        onCodeSent();
      } else {
        final err = _decodeError(response.body);
        onError('Server error: $err');
      }
    } catch (e) {
      debugPrint("HTTP Error: $e");
      onError('Failed to connect to OTP server.');
    }
  }

  /// Verifies [code] for [email] on the backend.
  Future<bool> verifyOtp({
    required String email,
    required String code,
  }) async {
    try {
      final response = await http.post(
        _endpoint('verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': code,
        }),
      );

      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['success'] == true;
    } catch (e) {
      debugPrint("HTTP Error: $e");
      return false;
    }
  }

  Future<void> linkPasswordResetEmail({
    required String username,
    required String email,
  }) async {
    try {
      await http.post(
        _endpoint('password/link-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
        }),
      );
    } catch (e) {
      debugPrint("Password reset email link failed: $e");
    }
  }

  Future<String?> startPasswordReset({
    required String username,
    required String email,
  }) async {
    try {
      final response = await http.post(
        _endpoint('password/reset/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
        }),
      );
      if (response.statusCode == 200) return null;
      return _decodeError(response.body);
    } catch (e) {
      debugPrint("Password reset start failed: $e");
      return 'Failed to connect to password reset server.';
    }
  }

  Future<String?> completePasswordReset({
    required String username,
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        _endpoint('password/reset/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'otp': otp,
          'newPassword': newPassword,
        }),
      );
      if (response.statusCode == 200) return null;
      return _decodeError(response.body);
    } catch (e) {
      debugPrint("Password reset complete failed: $e");
      return 'Failed to connect to password reset server.';
    }
  }

  String _decodeError(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['error']?.toString() ?? 'Unknown error';
    } catch (_) {
      return body.isEmpty ? 'Unknown error' : body;
    }
  }
}
