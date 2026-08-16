import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/config/media_upload_policy.dart';
import 'package:xmo/services/matrix_encrypted_media_helper.dart';
import 'package:xmo/services/xmo_chunked_media_upload_service.dart';

void main() {
  group('XmoChunkedMediaUploadService', () {
    test('uses current media path below threshold or for non-video media', () {
      const service = XmoChunkedMediaUploadService(
        thresholdBytes: 10,
        chunkSize: 4,
      );

      expect(
        service.shouldUploadAsStream(size: 9, mimeType: 'video/mp4'),
        isFalse,
      );
      expect(
        service.shouldUploadAsStream(size: 10, mimeType: 'image/jpeg'),
        isFalse,
      );
      expect(
        service.shouldUploadAsStream(size: 10, mimeType: 'video/mp4'),
        isTrue,
      );
    });

    test('splits, encrypts, uploads, and builds a source manifest', () async {
      final uploadedChunks = <_UploadedChunk>[];
      final service = XmoChunkedMediaUploadService(
        chunkSize: 4,
        thresholdBytes: 4,
        encryptedMediaHelper: MatrixEncryptedMediaHelper(random: Random(7)),
      );
      final bytes = Uint8List.fromList(List<int>.generate(10, (i) => i));

      final manifest = await service.uploadVideoStream(
        videoBytes: bytes,
        videoFileName: 'clip.mp4',
        videoMimeType: 'video/mp4',
        durationMs: 1234,
        uploadChunk:
            ({
              required encryptedBytes,
              required fileName,
              required contentType,
              required chunkIndex,
            }) async {
              uploadedChunks.add(
                _UploadedChunk(
                  index: chunkIndex,
                  fileName: fileName,
                  contentType: contentType,
                  bytes: encryptedBytes,
                ),
              );
              return Uri.parse('mxc://server/chunk$chunkIndex');
            },
      );

      expect(uploadedChunks, hasLength(3));
      expect(uploadedChunks.map((chunk) => chunk.index), [0, 1, 2]);
      expect(uploadedChunks.map((chunk) => chunk.contentType).toSet(), {
        'application/octet-stream',
      });
      expect(uploadedChunks[0].fileName, 'clip.mp4.xmo-stream.source.0.chunk');
      expect(uploadedChunks[0].bytes.length, 4);
      expect(uploadedChunks[1].bytes.length, 4);
      expect(uploadedChunks[2].bytes.length, 2);

      final chunks = manifest.sourceQuality!.chunks;
      expect(manifest.mimeType, 'video/mp4');
      expect(manifest.size, 10);
      expect(manifest.chunkSize, 4);
      expect(manifest.durationMs, 1234);
      expect(chunks, hasLength(3));
      expect(chunks.map((chunk) => chunk.url), [
        'mxc://server/chunk0',
        'mxc://server/chunk1',
        'mxc://server/chunk2',
      ]);
      expect(chunks.map((chunk) => chunk.key).toSet(), hasLength(3));
      expect(chunks.map((chunk) => chunk.iv).toSet(), hasLength(3));
      expect(chunks.map((chunk) => chunk.sha256).toSet(), hasLength(3));
    });

    test('uploads compressed quality variants before encryption', () async {
      final uploadedChunks = <_UploadedChunk>[];
      final service = XmoChunkedMediaUploadService(
        chunkSize: 4,
        thresholdBytes: 4,
        encryptedMediaHelper: MatrixEncryptedMediaHelper(random: Random(8)),
        qualityVariantProvider: (source) async => [
          XmoVideoQualityVariant(
            name: '480p',
            bytes: Uint8List.fromList([9, 8, 7, 6, 5]),
            fileName: 'clip.480p.mp4',
            mimeType: 'video/mp4',
          ),
          XmoVideoQualityVariant(
            name: '240p',
            bytes: Uint8List.fromList([4, 3, 2]),
            fileName: 'clip.240p.mp4',
            mimeType: 'video/mp4',
          ),
        ],
      );

      final manifest = await service.uploadVideoStream(
        videoBytes: Uint8List.fromList(List<int>.generate(10, (i) => i)),
        videoFileName: 'clip.mp4',
        videoMimeType: 'video/mp4',
        durationMs: 1234,
        uploadChunk:
            ({
              required encryptedBytes,
              required fileName,
              required contentType,
              required chunkIndex,
            }) async {
              uploadedChunks.add(
                _UploadedChunk(
                  index: chunkIndex,
                  fileName: fileName,
                  contentType: contentType,
                  bytes: encryptedBytes,
                ),
              );
              return Uri.parse('mxc://server/$fileName');
            },
      );

      expect(manifest.qualities.keys, containsAll(['source', '480p', '240p']));
      expect(manifest.quality('480p')!.size, 5);
      expect(manifest.quality('480p')!.chunkSize, 4);
      expect(manifest.quality('240p')!.size, 3);
      expect(manifest.quality('240p')!.chunks, hasLength(1));
      expect(
        uploadedChunks.map((chunk) => chunk.fileName),
        containsAll([
          'clip.480p.mp4.xmo-stream.480p.0.chunk',
          'clip.240p.mp4.xmo-stream.240p.0.chunk',
        ]),
      );
      expect(uploadedChunks.map((chunk) => chunk.contentType).toSet(), {
        'application/octet-stream',
      });
    });

    test('keeps source only when quality provider fails', () async {
      final service = XmoChunkedMediaUploadService(
        chunkSize: 4,
        thresholdBytes: 4,
        encryptedMediaHelper: MatrixEncryptedMediaHelper(random: Random(9)),
        qualityVariantProvider: (_) async =>
            throw StateError('compress failed'),
      );

      final manifest = await service.uploadVideoStream(
        videoBytes: Uint8List.fromList(List<int>.generate(10, (i) => i)),
        videoFileName: 'clip.mp4',
        videoMimeType: 'video/mp4',
        durationMs: null,
        uploadChunk:
            ({
              required encryptedBytes,
              required fileName,
              required contentType,
              required chunkIndex,
            }) async => Uri.parse('mxc://server/$fileName'),
      );

      expect(manifest.qualities.keys, ['source']);
    });

    test('normalizes video source when provider returns smaller mp4', () async {
      String? receivedSourcePath;
      final service = XmoChunkedMediaUploadService(
        sourceNormalizer: (source) async {
          receivedSourcePath = source.sourcePath;
          return XmoVideoQualityVariant(
            name: 'source',
            bytes: Uint8List.fromList([1, 2, 3]),
            fileName: 'clip.mp4',
            mimeType: 'video/mp4',
          );
        },
      );

      final normalized = await service.normalizeVideoSource(
        videoBytes: Uint8List.fromList(List<int>.filled(8, 9)),
        videoFileName: 'clip.mov',
        videoMimeType: 'video/quicktime',
        durationMs: 1000,
        sourcePath: '/queue/clip.mov',
      );

      expect(normalized, isNotNull);
      expect(normalized!.fileName, 'clip.mp4');
      expect(normalized.mimeType, 'video/mp4');
      expect(normalized.bytes, [1, 2, 3]);
      expect(receivedSourcePath, '/queue/clip.mov');
    });

    test('keeps original source when normalized video is larger', () async {
      final service = XmoChunkedMediaUploadService(
        sourceNormalizer: (source) async => XmoVideoQualityVariant(
          name: 'source',
          bytes: Uint8List.fromList(List<int>.filled(8, 1)),
          fileName: 'clip.mp4',
          mimeType: 'video/mp4',
        ),
      );

      final normalized = await service.normalizeVideoSource(
        videoBytes: Uint8List.fromList([1, 2, 3, 4]),
        videoFileName: 'clip.mp4',
        videoMimeType: 'video/mp4',
        durationMs: null,
      );

      expect(normalized, isNull);
    });

    test('keeps original source when source normalizer fails', () async {
      final service = XmoChunkedMediaUploadService(
        sourceNormalizer: (_) async => throw StateError('normalize failed'),
      );

      final normalized = await service.normalizeVideoSource(
        videoBytes: Uint8List.fromList([1, 2, 3, 4]),
        videoFileName: 'clip.mp4',
        videoMimeType: 'video/mp4',
        durationMs: null,
      );

      expect(normalized, isNull);
    });

    test('skips compressed variants that are larger than source', () async {
      final service = XmoChunkedMediaUploadService(
        chunkSize: 4,
        thresholdBytes: 4,
        encryptedMediaHelper: MatrixEncryptedMediaHelper(random: Random(10)),
        qualityVariantProvider: (_) async => [
          XmoVideoQualityVariant(
            name: '480p',
            bytes: Uint8List.fromList(List<int>.filled(10, 1)),
            fileName: 'clip.480p.mp4',
            mimeType: 'video/mp4',
          ),
        ],
      );

      final manifest = await service.uploadVideoStream(
        videoBytes: Uint8List.fromList(List<int>.generate(10, (i) => i)),
        videoFileName: 'clip.mp4',
        videoMimeType: 'video/mp4',
        durationMs: null,
        uploadChunk:
            ({
              required encryptedBytes,
              required fileName,
              required contentType,
              required chunkIndex,
            }) async => Uri.parse('mxc://server/$fileName'),
      );

      expect(manifest.qualities.keys, ['source']);
    });

    test('cancels when provider reports cancellation', () async {
      final service = XmoChunkedMediaUploadService(
        chunkSize: 4,
        thresholdBytes: 4,
        qualityVariantProvider: (_) async {
          throw const XmoChunkedMediaUploadCancelledException();
        },
      );

      expect(
        () => service.uploadVideoStream(
          videoBytes: Uint8List.fromList(List<int>.generate(10, (i) => i)),
          videoFileName: 'clip.mp4',
          videoMimeType: 'video/mp4',
          durationMs: null,
          uploadChunk:
              ({
                required encryptedBytes,
                required fileName,
                required contentType,
                required chunkIndex,
              }) async => Uri.parse('mxc://server/$fileName'),
        ),
        throwsA(isA<XmoChunkedMediaUploadCancelledException>()),
      );
    });

    test('throws cancellation before uploading the first chunk', () async {
      const service = XmoChunkedMediaUploadService(
        chunkSize: 4,
        thresholdBytes: 4,
      );

      expect(
        () => service.uploadVideoStream(
          videoBytes: Uint8List.fromList([1, 2, 3, 4]),
          videoFileName: 'clip.mp4',
          videoMimeType: 'video/mp4',
          durationMs: null,
          isCancelled: () => true,
          uploadChunk:
              ({
                required encryptedBytes,
                required fileName,
                required contentType,
                required chunkIndex,
              }) async => Uri.parse('mxc://server/chunk$chunkIndex'),
        ),
        throwsA(isA<XmoChunkedMediaUploadCancelledException>()),
      );
    });

    test('rejects video above the configured upload limit', () async {
      const service = XmoChunkedMediaUploadService(
        chunkSize: 4,
        thresholdBytes: 4,
        maxUploadBytes: 5,
      );

      await expectLater(
        service.uploadVideoStream(
          videoBytes: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
          videoFileName: 'large.mp4',
          videoMimeType: 'video/mp4',
          durationMs: null,
          uploadChunk:
              ({
                required encryptedBytes,
                required fileName,
                required contentType,
                required chunkIndex,
              }) async => Uri.parse('mxc://server/chunk'),
        ),
        throwsA(isA<MediaUploadPolicyException>()),
      );
    });
  });
}

class _UploadedChunk {
  final int index;
  final String fileName;
  final String contentType;
  final Uint8List bytes;

  const _UploadedChunk({
    required this.index,
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });
}
