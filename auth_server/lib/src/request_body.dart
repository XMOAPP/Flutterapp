import 'dart:convert';
import 'dart:typed_data';

/// Maximum accepted JSON request size for the auth service.
const maxAuthRequestBytes = 1024 * 1024;

class RequestBodyTooLargeException implements Exception {
  const RequestBodyTooLargeException();
}

class JsonRequestBodyException implements Exception {
  const JsonRequestBodyException(this.message);

  final String message;
}

/// Reads a JSON object while enforcing [maxBytes] as bytes arrive.
///
/// This also protects requests with no Content-Length, including chunked
/// transfer-encoded requests. [declaredContentLength] is only an early reject;
/// every received chunk is still counted.
Future<Map<String, dynamic>> readBoundedJsonObject(
  Stream<List<int>> body, {
  int? declaredContentLength,
  int maxBytes = maxAuthRequestBytes,
}) async {
  if (maxBytes < 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must not be negative');
  }
  if (declaredContentLength != null && declaredContentLength > maxBytes) {
    throw const RequestBodyTooLargeException();
  }

  final bytes = BytesBuilder(copy: false);
  var receivedBytes = 0;
  await for (final chunk in body) {
    receivedBytes += chunk.length;
    if (receivedBytes > maxBytes) {
      throw const RequestBodyTooLargeException();
    }
    bytes.add(chunk);
  }

  final raw = bytes.takeBytes();
  if (raw.isEmpty) {
    return <String, dynamic>{};
  }

  late final String text;
  try {
    text = utf8.decode(raw);
  } on FormatException {
    throw const JsonRequestBodyException('Invalid JSON request body');
  }
  if (text.trim().isEmpty) {
    return <String, dynamic>{};
  }

  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const JsonRequestBodyException(
        'JSON request body must be an object',
      );
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } on FormatException {
    throw const JsonRequestBodyException('Invalid JSON request body');
  }
}
