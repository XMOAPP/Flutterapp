import 'dart:convert';
import 'dart:io';

class StructuredLogger {
  const StructuredLogger();

  void request({
    required HttpRequest request,
    required int statusCode,
    required Duration elapsed,
  }) {
    stdout.writeln(jsonEncode({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': statusCode >= 500 ? 'error' : 'info',
      'event': 'http_request',
      'method': request.method,
      'path': request.uri.path,
      'status': statusCode,
      'elapsed_ms': elapsed.inMilliseconds,
      'remote': _remote(request),
    }));
  }

  void error(String event, Object error, StackTrace stackTrace) {
    stderr.writeln(jsonEncode({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': 'error',
      'event': event,
      'error': error.toString(),
      'stack': stackTrace.toString(),
    }));
  }

  String _remote(HttpRequest request) =>
      request.headers.value('x-forwarded-for') ??
      request.connectionInfo?.remoteAddress.address ??
      'unknown';
}
