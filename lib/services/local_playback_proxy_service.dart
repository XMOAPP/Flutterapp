import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'streaming_media_service.dart';

class XmoLocalPlaybackProxyException implements Exception {
  const XmoLocalPlaybackProxyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class XmoLocalPlaybackHandle {
  XmoLocalPlaybackHandle._({
    required this.uri,
    required this.session,
    required Future<void> Function() closeCallback,
  }) : _closeCallback = closeCallback;

  final Uri uri;
  final XmoStreamingMediaSession session;
  final Future<void> Function() _closeCallback;

  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _closeCallback();
  }
}

class LocalPlaybackProxyService {
  LocalPlaybackProxyService();

  static int _nextToken = 0;

  final Map<String, XmoStreamingMediaSession> _sessions =
      <String, XmoStreamingMediaSession>{};

  HttpServer? _server;

  bool get isRunning => _server != null;

  Future<XmoLocalPlaybackHandle> serveSession(
    XmoStreamingMediaSession session,
  ) async {
    final server = await _ensureServer();
    final token = _registerSession(session);
    final uri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: <String>['stream', token],
    );
    return XmoLocalPlaybackHandle._(
      uri: uri,
      session: session,
      closeCallback: () async {
        _sessions.remove(token);
        session.cancel();
        if (_sessions.isEmpty) {
          await stop();
        }
      },
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    for (final session in _sessions.values) {
      session.cancel();
    }
    _sessions.clear();
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<HttpServer> _ensureServer() async {
    final current = _server;
    if (current != null) return current;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_listen(server));
    return server;
  }

  Future<void> _listen(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  String _registerSession(XmoStreamingMediaSession session) {
    final token = '${DateTime.now().microsecondsSinceEpoch}_${_nextToken++}';
    _sessions[token] = session;
    return token;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        await _sendEmpty(request, HttpStatus.methodNotAllowed);
        return;
      }

      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments[0] != 'stream') {
        await _sendEmpty(request, HttpStatus.notFound);
        return;
      }

      final session = _sessions[segments[1]];
      if (session == null) {
        await _sendEmpty(request, HttpStatus.notFound);
        return;
      }

      final range = _parseRange(
        request.headers.value(HttpHeaders.rangeHeader),
        session.totalBytes,
      );
      if (range == null) {
        await _sendInvalidRange(request, session.totalBytes);
        return;
      }

      await _sendRange(
        request,
        session: session,
        range: range,
      );
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // Headers may already be on the wire. Closing is enough for the client.
      }
      await _closeResponseQuietly(request.response);
    }
  }

  Future<void> _sendRange(
    HttpRequest request, {
    required XmoStreamingMediaSession session,
    required _ByteRange range,
  }) async {
    final totalSize = session.totalBytes;
    final isPartial = range.start != 0 || range.end != totalSize - 1;
    final response = request.response;
    response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, session.mimeType)
      ..set(HttpHeaders.contentLengthHeader, range.length);
    if (isPartial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$totalSize',
      );
    }

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    try {
      await _writeBytesForRange(response, session, range);
    } on XmoStreamingMediaException {
      try {
        response.statusCode = HttpStatus.serviceUnavailable;
      } catch (_) {
        // Headers may already be on the wire. Closing is enough for the client.
      }
    } finally {
      await _closeResponseQuietly(response);
    }
  }

  Future<void> _writeBytesForRange(
    HttpResponse response,
    XmoStreamingMediaSession session,
    _ByteRange range,
  ) async {
    var position = range.start;
    while (position <= range.end) {
      final chunkIndex = position ~/ session.chunkSize;
      final chunkStart = chunkIndex * session.chunkSize;
      final offsetInChunk = position - chunkStart;
      final chunkEndExclusive = min(
        chunkStart + session.chunkSize,
        session.totalBytes,
      );
      final bytesToRead = min(
        range.end - position + 1,
        chunkEndExclusive - position,
      );

      final chunkFile = await session.ensureChunk(chunkIndex);
      final raf = await chunkFile.open();
      try {
        await raf.setPosition(offsetInChunk);
        final bytes = await raf.read(bytesToRead);
        response.add(bytes);
        await response.flush();
      } finally {
        await raf.close();
      }
      position += bytesToRead;
    }
  }

  _ByteRange? _parseRange(String? header, int totalSize) {
    if (totalSize <= 0) return null;
    if (header == null || header.trim().isEmpty) {
      return _ByteRange(0, totalSize - 1);
    }

    final value = header.trim();
    if (!value.startsWith('bytes=')) return null;
    final spec = value.substring('bytes='.length).trim();
    if (spec.contains(',')) return null;

    final dashIndex = spec.indexOf('-');
    if (dashIndex < 0) return null;
    final startText = spec.substring(0, dashIndex).trim();
    final endText = spec.substring(dashIndex + 1).trim();

    int start;
    int end;
    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0) return null;
      start = max(0, totalSize - suffixLength);
      end = totalSize - 1;
    } else {
      start = int.tryParse(startText) ?? -1;
      end = endText.isEmpty ? totalSize - 1 : int.tryParse(endText) ?? -1;
    }

    if (start < 0 || end < start || start >= totalSize) return null;
    end = min(end, totalSize - 1);
    return _ByteRange(start, end);
  }

  Future<void> _sendInvalidRange(HttpRequest request, int totalSize) async {
    final response = request.response;
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentRangeHeader, 'bytes */$totalSize');
    await response.close();
  }

  Future<void> _sendEmpty(HttpRequest request, int statusCode) async {
    request.response.statusCode = statusCode;
    await request.response.close();
  }
}

Future<void> _closeResponseQuietly(HttpResponse response) async {
  try {
    await response.close();
  } catch (_) {
    // The video player may close the socket while seeking or leaving the page.
  }
}

class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;
}
