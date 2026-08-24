import 'dart:convert';
import 'dart:io';

Future<Map<String, Object?>> readJsonObject(
  HttpRequest request, {
  int maxBytes = 65536,
}) async {
  final chunks = <int>[];
  await for (final chunk in request) {
    chunks.addAll(chunk);
    if (chunks.length > maxBytes) {
      throw const FormatException('Request body too large');
    }
  }

  final body = utf8.decode(chunks);
  if (body.trim().isEmpty) return <String, Object?>{};

  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException('Expected JSON object');
  }

  return decoded.cast<String, Object?>();
}

void sendJson(
  HttpRequest request,
  int statusCode,
  Map<String, Object?> body,
) {
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}
