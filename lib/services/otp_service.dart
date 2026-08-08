import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class OtpVerificationResult {
  const OtpVerificationResult({
    required this.verified,
    this.secureLoginEnrollmentProof,
    this.error,
  });

  final bool verified;
  final String? secureLoginEnrollmentProof;
  final String? error;
}

class SecureLoginProvisionResult {
  const SecureLoginProvisionResult({required this.success, this.error});

  final bool success;
  final String? error;
}

/// Handles Email OTP Authentication via local SMTP server.
class OtpService {
  static final OtpService _instance = OtpService._internal();
  factory OtpService() => _instance;
  OtpService._internal();

  Uri get _otpBaseUri {
    final value = AppConfig.otpServerUrl.trim();
    final normalized = value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
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
        body: jsonEncode({'email': email}),
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
  Future<OtpVerificationResult> verifyOtp({
    required String email,
    required String code,
  }) async {
    try {
      final response = await http.post(
        _endpoint('verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': code}),
      );

      if (response.statusCode != 200) {
        return OtpVerificationResult(
          verified: false,
          error: _decodeError(response.body),
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final proof = data['secureLoginEnrollmentProof']?.toString();
      return OtpVerificationResult(
        verified: data['success'] == true,
        secureLoginEnrollmentProof: proof == null || proof.trim().isEmpty
            ? null
            : proof.trim(),
      );
    } catch (e) {
      debugPrint("HTTP Error: $e");
      return const OtpVerificationResult(
        verified: false,
        error: 'Failed to connect to OTP server.',
      );
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
        body: jsonEncode({'username': username, 'email': email}),
      );
    } catch (e) {
      debugPrint("Password reset email link failed: $e");
    }
  }

  Future<SecureLoginProvisionResult> provisionSecureLogin({
    required String username,
    required String email,
    required String password,
    required String accessToken,
    required String secureLoginEnrollmentProof,
    String? displayName,
  }) async {
    if (accessToken.trim().isEmpty ||
        secureLoginEnrollmentProof.trim().isEmpty) {
      return const SecureLoginProvisionResult(
        success: false,
        error: 'Secure sign-in verification is missing. Please try again.',
      );
    }
    try {
      final response = await http.post(
        _endpoint('users/provision-secure-login'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${accessToken.trim()}',
        },
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'secureLoginEnrollmentProof': secureLoginEnrollmentProof,
          if (displayName != null && displayName.trim().isNotEmpty)
            'displayName': displayName.trim(),
        }),
      );
      if (response.statusCode != 200) {
        final error = _decodeError(response.body);
        debugPrint('Secure sign-in provisioning failed: $error');
        return SecureLoginProvisionResult(success: false, error: error);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        return const SecureLoginProvisionResult(success: true);
      }
      final error =
          data['error']?.toString() ?? 'Secure sign-in is unavailable.';
      debugPrint('Secure sign-in provisioning skipped: $error');
      return SecureLoginProvisionResult(success: false, error: error);
    } catch (e) {
      debugPrint('Secure sign-in provisioning failed: $e');
      return const SecureLoginProvisionResult(
        success: false,
        error: 'Could not prepare secure sign-in. Please try again.',
      );
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
        body: jsonEncode({'username': username, 'email': email}),
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
