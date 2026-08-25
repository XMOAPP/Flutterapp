import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/xmo_stream_manifest.dart';
import 'package:xmo/services/local_playback_proxy_service.dart';
import 'package:xmo/services/matrix_encrypted_media_helper.dart';
import 'package:xmo/services/matrix_media_helper.dart';
import 'package:xmo/services/streaming_media_service.dart';

class _DeterministicRandom implements Random {
  _DeterministicRandom(this._bytes);

  final List<int> _bytes;
  int _index = 0;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);

  @override
  int nextInt(int max) {
    final value = _bytes[_index % _bytes.length];
    _index += 1;
    return value % max;
  }
}

void main() {
  group('LocalPlaybackProxyService', () {
    late Directory tempRoot;
    late MatrixEncryptedMediaHelper encryptedMediaHelper;
    late LocalPlaybackProxyService proxy;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('xmo_proxy_test_');
      encryptedMediaHelper = MatrixEncryptedMediaHelper(
        random: _DeterministicRandom(List<int>.generate(256, (i) => i + 1)),
      );
      proxy = LocalPlaybackProxyService();
    });

    tearDown(() async {
      await proxy.stop();
      if (await tempRoot.exists()) {
        await _deleteDirectoryWithRetry(tempRoot);
      }
    });

    test('serves the full decrypted media body', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
        'efgh',
        'ij',
      ]);

      final response = await _get(handle.uri);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(
        response.headers.value(HttpHeaders.cacheControlHeader),
        'no-store',
      );
      expect(response.headers.contentLength, 10);
      expect(utf8.decode(response.body), 'abcdefghij');

      await handle.close();
    });

    test('uses an unguessable local stream token', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
      ]);

      final token = handle.uri.pathSegments.last;
      expect(token, hasLength(43));
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(token, isNot(startsWith('stream_')));

      await handle.close();
    });

    test('serves partial byte ranges across chunk boundaries', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
        'efgh',
        'ij',
      ]);

      final response = await _get(
        handle.uri,
        headers: {HttpHeaders.rangeHeader: 'bytes=2-6'},
      );

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 2-6/10',
      );
      expect(response.headers.contentLength, 5);
      expect(utf8.decode(response.body), 'cdefg');

      await handle.close();
    });

    test('serves suffix byte ranges', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
        'efgh',
        'ij',
      ]);

      final response = await _get(
        handle.uri,
        headers: {HttpHeaders.rangeHeader: 'bytes=-3'},
      );

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 7-9/10',
      );
      expect(utf8.decode(response.body), 'hij');

      await handle.close();
    });

    test('serves selected lower quality using its own byte size', () async {
      final sourceFixture = await _buildFixture(encryptedMediaHelper, [
        'source',
        '-video',
      ]);
      final lowFixture = await _buildFixture(encryptedMediaHelper, [
        'low',
        '-q',
      ]);
      final manifest = XmoStreamManifest(
        version: XmoStreamManifest.supportedVersion,
        mimeType: 'video/mp4',
        size: sourceFixture.manifest.size,
        chunkSize: sourceFixture.manifest.chunkSize,
        qualities: {
          'source': sourceFixture.manifest.sourceQuality!,
          '240p': XmoStreamQuality(
            size: lowFixture.manifest.size,
            chunkSize: lowFixture.manifest.chunkSize,
            mimeType: 'video/mp4',
            chunks: lowFixture.manifest.sourceQuality!.chunks,
          ),
        },
      );
      final streamingService = _streamingService(
        tempRoot,
        encryptedMediaHelper,
        downloader: (request, chunk) async =>
            lowFixture.encryptedChunks[chunk.index]!,
      );
      final session = await streamingService.open(
        eventId: 'proxy-low-quality',
        manifest: manifest,
        quality: '240p',
      );
      final handle = await proxy.serveSession(session);

      final response = await _get(handle.uri);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentLength, 5);
      expect(utf8.decode(response.body), 'low-q');

      await handle.close();
    });

    test('rejects invalid ranges', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
        'efgh',
        'ij',
      ]);

      final response = await _get(
        handle.uri,
        headers: {HttpHeaders.rangeHeader: 'bytes=99-100'},
      );

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */10',
      );

      await handle.close();
    });

    test('rejects unsupported HTTP methods', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
      ]);

      final response = await _request(handle.uri, 'POST');

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(response.headers.value(HttpHeaders.allowHeader), 'GET, HEAD');

      await handle.close();
    });

    test('rejects invalid stream tokens', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
      ]);

      final response = await _get(
        handle.uri.replace(pathSegments: <String>['stream', 'short']),
      );

      expect(response.statusCode, HttpStatus.notFound);

      await handle.close();
    });

    test('serves HEAD metadata without a response body', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
        'efgh',
      ]);

      final response = await _request(handle.uri, 'HEAD');

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentLength, 8);
      expect(response.body, isEmpty);

      await handle.close();
    });

    test('waits for a requested chunk while it downloads', () async {
      final fixture = await _buildFixture(encryptedMediaHelper, [
        'abcd',
        'efgh',
      ]);
      final delayedChunk = Completer<Uint8List>();
      final streamingService = _streamingService(
        tempRoot,
        encryptedMediaHelper,
        downloader: (request, chunk) async {
          if (chunk.index == 1) return delayedChunk.future;
          return fixture.encryptedChunks[chunk.index]!;
        },
      );
      final session = await streamingService.open(
        eventId: 'wait-event',
        manifest: fixture.manifest,
      );
      final handle = await proxy.serveSession(session);

      final bodyFuture = _get(
        handle.uri,
        headers: {HttpHeaders.rangeHeader: 'bytes=4-7'},
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delayedChunk.isCompleted, isFalse);
      delayedChunk.complete(fixture.encryptedChunks[1]!);

      final response = await bodyFuture.timeout(const Duration(seconds: 3));
      expect(response.statusCode, HttpStatus.partialContent);
      expect(utf8.decode(response.body), 'efgh');

      await handle.close();
      await session.cleanup();
    });

    test('closing a handle cancels the session and stops the server', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
      ]);

      expect(proxy.isRunning, isTrue);
      await handle.close();

      expect(handle.session.isCancelled, isTrue);
      expect(proxy.isRunning, isFalse);
    });

    test('stopping the proxy cancels active sessions', () async {
      final handle = await _openHandle(proxy, tempRoot, encryptedMediaHelper, [
        'abcd',
      ]);

      await proxy.stop();

      expect(handle.session.isCancelled, isTrue);
      expect(proxy.isRunning, isFalse);
    });
  });
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  const attempts = 5;
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } on FileSystemException {
      if (attempt == attempts - 1) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<XmoLocalPlaybackHandle> _openHandle(
  LocalPlaybackProxyService proxy,
  Directory tempRoot,
  MatrixEncryptedMediaHelper encryptedMediaHelper,
  List<String> clearChunks,
) async {
  final fixture = await _buildFixture(encryptedMediaHelper, clearChunks);
  final streamingService = _streamingService(
    tempRoot,
    encryptedMediaHelper,
    downloader: (request, chunk) async => fixture.encryptedChunks[chunk.index]!,
  );
  final session = await streamingService.open(
    eventId: 'proxy-event-${clearChunks.join()}',
    manifest: fixture.manifest,
  );
  return proxy.serveSession(session);
}

StreamingMediaService _streamingService(
  Directory tempRoot,
  MatrixEncryptedMediaHelper encryptedMediaHelper, {
  required XmoStreamChunkDownloader downloader,
}) {
  return StreamingMediaService(
    mediaHelper: const MatrixMediaHelper(
      homeserverUrl: 'https://matrix.example.org',
      accessToken: 'test-token',
    ),
    encryptedMediaHelper: encryptedMediaHelper,
    downloader: downloader,
    cacheDirectoryProvider: () async => tempRoot,
  );
}

Future<_HttpTestResponse> _get(
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
}) {
  return _request(uri, 'GET', headers: headers);
}

Future<_HttpTestResponse> _request(
  Uri uri,
  String method, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = <int>[];
    await for (final chunk in response) {
      body.addAll(chunk);
    }
    return _HttpTestResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: Uint8List.fromList(body),
    );
  } finally {
    client.close(force: true);
  }
}

Future<_StreamFixture> _buildFixture(
  MatrixEncryptedMediaHelper encryptedMediaHelper,
  List<String> clearChunks,
) async {
  final encryptedChunks = <int, Uint8List>{};
  final streamChunks = <XmoStreamChunk>[];

  for (var i = 0; i < clearChunks.length; i++) {
    final encrypted = await encryptedMediaHelper.encrypt(
      Uint8List.fromList(utf8.encode(clearChunks[i])),
    );
    encryptedChunks[i] = encrypted.data;
    streamChunks.add(
      XmoStreamChunk(
        index: i,
        url: 'mxc://server/chunk$i',
        key: encrypted.k,
        iv: encrypted.iv,
        sha256: encrypted.sha256,
      ),
    );
  }

  return _StreamFixture(
    encryptedChunks: encryptedChunks,
    manifest: XmoStreamManifest(
      version: XmoStreamManifest.supportedVersion,
      mimeType: 'video/mp4',
      size: clearChunks.fold<int>(
        0,
        (total, chunk) => total + utf8.encode(chunk).length,
      ),
      chunkSize: clearChunks.first.length,
      qualities: {'source': XmoStreamQuality(chunks: streamChunks)},
    ),
  );
}

class _StreamFixture {
  const _StreamFixture({required this.encryptedChunks, required this.manifest});

  final Map<int, Uint8List> encryptedChunks;
  final XmoStreamManifest manifest;
}

class _HttpTestResponse {
  const _HttpTestResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final Uint8List body;
}
