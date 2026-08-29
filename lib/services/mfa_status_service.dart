import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class MfaStatusService {
  const MfaStatusService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<bool> isTotpEnrolled({required String accessToken}) async {
    final token = accessToken.trim();
    if (token.isEmpty) throw const MfaStatusException();

    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(_endpoint(), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded is! Map) {
        throw const MfaStatusException();
      }
      if (decoded['success'] != true || decoded['enrolled'] is! bool) {
        throw const MfaStatusException();
      }
      return decoded['enrolled'] as bool;
    } catch (error) {
      if (error is MfaStatusException) rethrow;
      throw const MfaStatusException();
    } finally {
      if (_client == null) client.close();
    }
  }

  Uri _endpoint() {
    final configured = AppConfig.userDirectoryServerUrl.trim();
    final normalized = configured.endsWith('/')
        ? configured.substring(0, configured.length - 1)
        : configured;
    final base = Uri.parse(normalized);
    return base.replace(path: '${base.path}/security/mfa-status');
  }
}

class MfaStatusException implements Exception {
  const MfaStatusException();
}
