import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/report_models.dart';
import 'matrix_service.dart';

class ReportService {
  ReportService(this._matrixService);

  final MatrixService _matrixService;

  Future<void> submitReport({
    required XmoReportTargetType targetType,
    required XmoReportContextType contextType,
    required XmoReportReason reason,
    String? reportedUserId,
    String? roomId,
    String? eventId,
    String? details,
  }) async {
    final token = _matrixService.accessToken;
    if (token == null || token.isEmpty) throw Exception('Not signed in');

    final payload = {
      'targetType': targetType.name,
      'contextType': contextType.name,
      'reason': reason.code,
      if (reportedUserId?.isNotEmpty == true) 'reportedUserId': reportedUserId,
      if (roomId?.isNotEmpty == true) 'roomId': roomId,
      if (eventId?.isNotEmpty == true) 'eventId': eventId,
      if (details?.trim().isNotEmpty == true) 'details': details!.trim(),
    };

    try {
      final response = await http
          .post(
            _endpoint('reports/submit'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      final body = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(body['error']?.toString() ?? 'Unable to submit report');
      }
      return;
    } catch (_) {
      if (targetType != XmoReportTargetType.message ||
          roomId == null ||
          eventId == null) {
        rethrow;
      }
      await _matrixService.client.reportEvent(
        roomId,
        eventId,
        reason:
            '${reason.label}${details?.trim().isNotEmpty == true ? ': ${details!.trim()}' : ''}',
      );
    }
  }

  Future<List<XmoModerationReport>> listRoomReports(String roomId) async {
    final response = await _postAuthenticated(
      'reports/review/list',
      {'roomId': roomId},
    );
    return _parseReports(response['reports']);
  }

  Future<List<XmoModerationReport>> listGlobalReports() async {
    final response = await _postAuthenticated(
      'reports/review/list',
      const {'global': true},
    );
    return _parseReports(response['reports']);
  }

  Future<bool> canReviewGlobalReports() async {
    try {
      await _postAuthenticated(
        'reports/review/list',
        const {'global': true, 'limit': 1},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  List<XmoModerationReport> _parseReports(Object? values) {
    if (values is! List) return const [];
    return values
        .whereType<Map>()
        .map((value) => value.map((key, item) => MapEntry('$key', item)))
        .map(XmoModerationReport.fromJson)
        .toList();
  }

  Future<void> updateReport({
    required String reportId,
    required XmoReportStatus status,
    String? moderatorNote,
  }) async {
    await _postAuthenticated('reports/review/update', {
      'reportId': reportId,
      'status': status.name,
      if (moderatorNote?.trim().isNotEmpty == true)
        'moderatorNote': moderatorNote!.trim(),
    });
  }

  Future<Map<String, dynamic>> _postAuthenticated(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = _matrixService.accessToken;
    if (token == null || token.isEmpty) throw Exception('Not signed in');
    final response = await http
        .post(
          _endpoint(path),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?.toString() ?? 'Request failed');
    }
    return decoded;
  }

  Uri _endpoint(String path) {
    final value = AppConfig.reportServerUrl.trim();
    final normalized =
        value.endsWith('/') ? value.substring(0, value.length - 1) : value;
    final base = Uri.parse(normalized);
    return base.replace(path: '${base.path}/$path');
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map) {
        return value.map((key, item) => MapEntry('$key', item));
      }
    } catch (_) {}
    return const {};
  }
}
