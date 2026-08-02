import 'dart:convert';
import 'dart:io';

class StructuredLogger {
  const StructuredLogger();

  void error(String message, Object error, StackTrace stackTrace) {
    logError(message, error, stackTrace);
  }

  void request({
    required HttpRequest request,
    required int statusCode,
    required Duration elapsed,
  }) {
    logInfo('request', {
      'method': request.method,
      'path': sanitizeRequestPath(request.uri.path),
      'statusCode': statusCode,
      'elapsedMs': elapsed.inMilliseconds,
    });
  }
}

String sanitizeRequestPath(String path) {
  return path.replaceAllMapped(
    RegExp(
      r'(^|/)(invites)/[A-Za-z0-9_-]{40,64}/(preview|redeem)(?=/|$)',
    ),
    (match) =>
        '${match.group(1)}${match.group(2)}/<redacted>/${match.group(3)}',
  );
}

void logInfo(String message, [Map<String, Object?> context = const {}]) {
  _log('info', message, context);
}

void logWarning(String message, [Map<String, Object?> context = const {}]) {
  _log('warning', message, context);
}

void logError(
  String message,
  Object error,
  StackTrace stackTrace, [
  Map<String, Object?> context = const {},
]) {
  _log('error', message, {
    ...context,
    'error': error.toString(),
    'stack': stackTrace.toString(),
  });
}

void _log(String level, String message, Map<String, Object?> context) {
  final entry = <String, Object?>{
    'time': DateTime.now().toUtc().toIso8601String(),
    'level': level,
    'message': message,
    if (context.isNotEmpty) 'context': context,
  };

  // ignore: avoid_print
  print(jsonEncode(entry));
}
