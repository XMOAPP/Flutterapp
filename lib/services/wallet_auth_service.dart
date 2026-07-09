import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class WalletAuthService {
  const WalletAuthService({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

  Uri get _baseUri {
    final value = AppConfig.walletAuthServerUrl.trim();
    final normalized =
        value.endsWith('/') ? value.substring(0, value.length - 1) : value;
    return Uri.parse(normalized);
  }

  Uri _endpoint(String path) {
    final base = _baseUri;
    return base.replace(path: '${base.path}/$path');
  }

  Future<WalletAuthChallenge> createChallenge({
    required String username,
    required String address,
    required String mode,
    required String walletType,
    String chainId = '1',
  }) async {
    final client = _httpClient ?? http.Client();
    try {
      final response = await client
          .post(
            _endpoint('nonce'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'address': address,
              'mode': mode,
              'walletType': walletType,
              'chainId': chainId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = _decode(response.body);
      if (response.statusCode != 200) {
        throw WalletAuthException(_errorFrom(body));
      }
      return WalletAuthChallenge.fromJson(body);
    } catch (e) {
      debugPrint('[WalletAuthService] createChallenge failed: $e');
      if (e is WalletAuthException) rethrow;
      throw const WalletAuthException('Could not start wallet sign-in.');
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  Future<WalletAuthVerification> verifySignature({
    required String username,
    required String address,
    required String mode,
    required String walletType,
    required String message,
    required String signature,
  }) async {
    final client = _httpClient ?? http.Client();
    try {
      final response = await client
          .post(
            _endpoint('verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'address': address,
              'mode': mode,
              'walletType': walletType,
              'message': message,
              'signature': signature,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = _decode(response.body);
      if (response.statusCode != 200) {
        throw WalletAuthException(_errorFrom(body));
      }
      return WalletAuthVerification.fromJson(body);
    } catch (e) {
      debugPrint('[WalletAuthService] verifySignature failed: $e');
      if (e is WalletAuthException) rethrow;
      throw const WalletAuthException('Could not verify wallet signature.');
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  String _errorFrom(Map<String, dynamic> body) =>
      body['error']?.toString() ?? 'Wallet authentication failed.';
}

class WalletAuthChallenge {
  const WalletAuthChallenge({
    required this.message,
    required this.nonce,
    required this.expiresAt,
  });

  final String message;
  final String nonce;
  final DateTime expiresAt;

  factory WalletAuthChallenge.fromJson(Map<String, dynamic> json) {
    return WalletAuthChallenge(
      message: json['message']?.toString() ?? '',
      nonce: json['nonce']?.toString() ?? '',
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class WalletAuthVerification {
  const WalletAuthVerification({
    required this.username,
    required this.address,
    required this.walletType,
    required this.matrixPassword,
  });

  final String username;
  final String address;
  final String walletType;
  final String matrixPassword;

  factory WalletAuthVerification.fromJson(Map<String, dynamic> json) {
    return WalletAuthVerification(
      username: json['username']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      walletType: json['walletType']?.toString() ?? 'evm',
      matrixPassword: json['matrixPassword']?.toString() ?? '',
    );
  }
}

class WalletAuthException implements Exception {
  const WalletAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
