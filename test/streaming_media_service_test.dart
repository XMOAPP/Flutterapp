import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/xmo_stream_manifest.dart';
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
  group('StreamingMediaService', () {
    late Directory tempRoot;
    late MatrixEncryptedMediaHelper encryptedMediaHelper;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('xmo_stream_test_');
      encryptedMediaHelper = MatrixEncryptedMediaHelper(
        random: _DeterministicRandom(List<int>.generate(256, (i) => i + 1)),
      );
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('downloads chunk 0 first, decrypts it, then prefetches next chunks',
        () async {
      final fixture = await _buildFixture(
        encryptedMediaHelper,
        ['first chunk', 'second chunk', 'third chunk'],
      );
      final requestedIndexes = <int>[];
      final service = _service(
        tempRoot,
        encryptedMediaHelper,
        downloader: (request, chunk) async {
          requestedIndexes.add(chunk.index);
          expect(request.headers['Authorization'], 'Bearer test-token');
          return fixture.encryptedChunks[chunk.index]!;
        },
      );

      final session = await service.openFromEventContent(
        eventId: r'$event/one',
        content: {xmoStreamContentKey: fixture.manifest.toJson()},
      );

      expect(requestedIndexes.first, 0);
      expect(await session.chunkFile(0).readAsString(), 'first chunk');

      await session.states
          .firstWhere((state) => state.phase == XmoStreamingMediaPhase.complete)
          .timeout(const Duration(seconds: 3));

      expect(await session.chunkFile(1).readAsString(), 'second chunk');
      expect(await session.chunkFile(2).readAsString(), 'third chunk');
      expect(requestedIndexes, [0, 1, 2]);

      await session.cleanup();
    });

    test('retries failed chunk downloads', () async {
      final fixture = await _buildFixture(
        encryptedMediaHelper,
        ['retry chunk'],
      );
      var attempts = 0;
      final service = _service(
        tempRoot,
        encryptedMediaHelper,
        maxRetries: 2,
        downloader: (request, chunk) async {
          attempts += 1;
          if (attempts == 1) {
            throw const SocketException('temporary failure');
          }
          return fixture.encryptedChunks[chunk.index]!;
        },
      );

      final session = await service.open(
        eventId: 'retry-event',
        manifest: fixture.manifest,
      );

      expect(attempts, 2);
      expect(await session.chunkFile(0).readAsString(), 'retry chunk');

      await session.cleanup();
    });

    test('rejects corrupted encrypted chunks', () async {
      final fixture = await _buildFixture(
        encryptedMediaHelper,
        ['valid chunk'],
      );
      final service = _service(
        tempRoot,
        encryptedMediaHelper,
        maxRetries: 1,
        downloader: (request, chunk) async {
          return Uint8List.fromList([1, 2, 3, 4]);
        },
      );

      expect(
        () => service.open(
          eventId: 'bad-hash-event',
          manifest: fixture.manifest,
        ),
        throwsA(isA<XmoStreamingMediaException>()),
      );
    });

    test('can recover a failed chunk by retrying it', () async {
      final fixture = await _buildFixture(
        encryptedMediaHelper,
        ['first chunk', 'second chunk'],
      );
      var failSecondChunk = true;
      final service = _service(
        tempRoot,
        encryptedMediaHelper,
        maxRetries: 1,
        downloader: (request, chunk) async {
          if (chunk.index == 1 && failSecondChunk) {
            throw const SocketException('temporary failure');
          }
          return fixture.encryptedChunks[chunk.index]!;
        },
      );

      final session = await service.open(
        eventId: 'recover-event',
        manifest: fixture.manifest,
      );

      await expectLater(
        () => session.ensureChunk(1),
        throwsA(isA<XmoStreamingMediaException>()),
      );

      failSecondChunk = false;
      await session.retryFailedChunk(1);
      expect(await session.chunkFile(1).readAsString(), 'second chunk');

      await session.cleanup();
    });

    test('cancels future chunk work', () async {
      final fixture = await _buildFixture(
        encryptedMediaHelper,
        ['first chunk', 'second chunk'],
      );
      final service = _service(
        tempRoot,
        encryptedMediaHelper,
        downloader: (request, chunk) async =>
            fixture.encryptedChunks[chunk.index]!,
      );

      final session = await service.open(
        eventId: 'cancel-event',
        manifest: fixture.manifest,
      );

      session.cancel();

      await expectLater(
        () => session.ensureChunk(1),
        throwsA(isA<XmoStreamingMediaException>()),
      );

      await session.cleanup();
    });

    test('reuses the same active session for duplicate opens', () async {
      final fixture = await _buildFixture(
        encryptedMediaHelper,
        ['first chunk'],
      );
      var downloadCount = 0;
      final service = _service(
        tempRoot,
        encryptedMediaHelper,
        downloader: (request, chunk) async {
          downloadCount += 1;
          return fixture.encryptedChunks[chunk.index]!;
        },
      );

      final first = await service.open(
        eventId: 'duplicate-event',
        manifest: fixture.manifest,
      );
      final second = await service.open(
        eventId: 'duplicate-event',
        manifest: fixture.manifest,
      );

      expect(identical(first, second), isTrue);
      expect(downloadCount, 1);

      await first.cleanup();
    });

    test('enforces cache size limit without deleting the protected chunk',
        () async {
      final fixture = await _buildFixture(
        encryptedMediaHelper,
        ['1111', '2222', '3333'],
      );
      final service = _service(
        tempRoot,
        encryptedMediaHelper,
        maxCacheBytes: 5,
        downloader: (request, chunk) async =>
            fixture.encryptedChunks[chunk.index]!,
      );

      final session = await service.open(
        eventId: 'cache-limit-event',
        manifest: fixture.manifest,
      );
      await session.ensureChunk(1);
      await session.ensureChunk(2);

      expect(await session.chunkFile(2).exists(), isTrue);
      expect(session.cachedBytes <= 5, isTrue);

      await session.cleanup();
      expect(await session.cacheDirectory.exists(), isFalse);
    });

    test('cleans expired cache directories and trims total cache size',
        () async {
      final oldDir = Directory('${tempRoot.path}${Platform.pathSeparator}old');
      final mediumDir =
          Directory('${tempRoot.path}${Platform.pathSeparator}medium');
      final newestDir =
          Directory('${tempRoot.path}${Platform.pathSeparator}newest');
      await oldDir.create(recursive: true);
      await mediumDir.create(recursive: true);
      await newestDir.create(recursive: true);

      final oldFile = File('${oldDir.path}${Platform.pathSeparator}chunk.bin');
      final mediumFile =
          File('${mediumDir.path}${Platform.pathSeparator}chunk.bin');
      final newestFile =
          File('${newestDir.path}${Platform.pathSeparator}chunk.bin');
      await oldFile.writeAsBytes(List<int>.filled(4, 1));
      await mediumFile.writeAsBytes(List<int>.filled(4, 2));
      await newestFile.writeAsBytes(List<int>.filled(4, 3));

      final now = DateTime(2026, 7, 5, 12);
      await oldFile.setLastModified(now.subtract(const Duration(days: 2)));
      await mediumFile.setLastModified(now.subtract(const Duration(hours: 2)));
      await newestFile
          .setLastModified(now.subtract(const Duration(minutes: 5)));

      await StreamingMediaService.cleanupCacheDirectory(
        tempRoot,
        maxAge: const Duration(days: 1),
        maxTotalBytes: 5,
        now: now,
      );

      expect(await oldDir.exists(), isFalse);
      expect(await mediumDir.exists(), isFalse);
      expect(await newestDir.exists(), isTrue);
    });
  });
}

StreamingMediaService _service(
  Directory tempRoot,
  MatrixEncryptedMediaHelper encryptedMediaHelper, {
  required XmoStreamChunkDownloader downloader,
  int maxRetries = 3,
  int maxCacheBytes = 256 * 1024 * 1024,
}) {
  return StreamingMediaService(
    mediaHelper: const MatrixMediaHelper(
      homeserverUrl: 'https://matrix.example.org',
      accessToken: 'test-token',
    ),
    encryptedMediaHelper: encryptedMediaHelper,
    downloader: downloader,
    cacheDirectoryProvider: () async => tempRoot,
    maxRetries: maxRetries,
    maxCacheBytes: maxCacheBytes,
  );
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
      chunkSize: 4,
      qualities: {
        'source': XmoStreamQuality(chunks: streamChunks),
      },
    ),
  );
}

class _StreamFixture {
  const _StreamFixture({
    required this.encryptedChunks,
    required this.manifest,
  });

  final Map<int, Uint8List> encryptedChunks;
  final XmoStreamManifest manifest;
}
