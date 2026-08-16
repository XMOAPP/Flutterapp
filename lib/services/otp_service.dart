import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xmo/utils/user_facing_error.dart';
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

class OidcAccountRegistrationResult {
  const OidcAccountRegistrationResult({required this.success, this.error});

  final bool success;
  final String? error;
}

class UsernameAvailabilityResult {
  const UsernameAvailabilityResult({
    required this.success,
    this.available,
    this.error,
  });

  final bool success;
  final bool? available;
  final String? error;
}

/// Handles Email OTP Authentication via local SMTP server.
class OtpService {
  static final OtpService _instance = OtpService._internal(http.Client());
  factory OtpService() => _instance;
  OtpService._internal(this._client, [this._otpServerUrlOverride]);

  @visibleForTesting
  factory OtpService.forTesting({
    required http.Client client,
    required String otpServerUrl,
  }) => OtpService._internal(client, otpServerUrl);

  final http.Client _client;
  final String? _otpServerUrlOverride;

  Uri get _otpBaseUri {
    final value = (_otpServerUrlOverride ?? AppConfig.otpServerUrl).trim();
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
      final response = await _client.post(
        _endpoint('send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        onCodeSent();
      } else {
        final err = _decodeError(response.body);
        onError(
          userFacingError(err, fallback: 'Could not send verification code.'),
        );
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
      final response = await _client.post(
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
      final normalizedProof = proof == null || proof.trim().isEmpty
          ? null
          : proof.trim();
      debugPrint(
        '[OtpService] OTP verification completed: '
        'success=${data['success'] == true}, '
        'hasSecureLoginEnrollmentProof=${normalizedProof != null}.',
      );
      return OtpVerificationResult(
        verified: data['success'] == true,
        secureLoginEnrollmentProof: normalizedProof,
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
      await _client.post(
        _endpoint('password/link-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'email': email}),
      );
    } catch (e) {
      debugPrint("Password reset email link failed: $e");
    }
  }

  Future<UsernameAvailabilityResult> checkUsernameAvailability(
    String username,
  ) async {
    try {
      final response = await _client.post(
        _endpoint('accounts/username-availability'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );
      if (response.statusCode != 200) {
        return UsernameAvailabilityResult(
          success: false,
          error: _decodeError(response.body),
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final available = data['available'];
      if (data['success'] != true || available is! bool) {
        return const UsernameAvailabilityResult(
          success: false,
          error: 'Could not verify username availability.',
        );
      }
      return UsernameAvailabilityResult(success: true, available: available);
    } catch (error) {
      debugPrint('Username availability check failed: $error');
      return const UsernameAvailabilityResult(
        success: false,
        error: 'Could not verify username availability. Please retry.',
      );
    }
  }

  Future<OidcAccountRegistrationResult> registerOidcAccount({
    required String username,
    required String email,
    required String password,
    required String secureLoginEnrollmentProof,
    String? displayName,
  }) async {
    if (secureLoginEnrollmentProof.trim().isEmpty) {
      return const OidcAccountRegistrationResult(
        success: false,
        error: 'Email verification expired. Please request a new code.',
      );
    }
    try {
      final response = await _client.post(
        _endpoint('accounts/register'),
        headers: {'Content-Type': 'application/json'},
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
        return OidcAccountRegistrationResult(
          success: false,
          error: _decodeError(response.body),
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return OidcAccountRegistrationResult(
        success: data['success'] == true,
        error: data['success'] == true
            ? null
            : userFacingError(
                data['error'],
                fallback: 'Could not create the account.',
              ),
      );
    } catch (error) {
      debugPrint('OIDC account registration failed: $error');
      return const OidcAccountRegistrationResult(
        success: false,
        error: 'Could not connect to the account server. Please retry.',
      );
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
      debugPrint('[OtpService] Requesting secure sign-in provisioning.');
      final response = await _client.post(
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
        return SecureLoginProvisionResult(
          success: false,
          error: _decodeError(response.body),
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        debugPrint('[OtpService] Secure sign-in provisioning completed.');
        return const SecureLoginProvisionResult(success: true);
      }
      return SecureLoginProvisionResult(
        success: false,
        error: userFacingError(
          data['error'],
          fallback: 'Secure sign-in is unavailable.',
        ),
      );
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
      final response = await _client.post(
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
      final response = await _client.post(
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
      return userFacingError(
        data['error'],
        fallback: 'The request could not be completed. Please try again.',
      );
    } catch (_) {
      return 'The request could not be completed. Please try again.';
    }
  }
}
