import 'dart:math';
import 'dart:typed_data';

import '../models/xmo_stream_manifest.dart';
import 'matrix_encrypted_media_helper.dart';

typedef XmoEncryptedChunkUploader = Future<Uri> Function({
  required Uint8List encryptedBytes,
  required String fileName,
  required String contentType,
  required int chunkIndex,
});

typedef XmoVideoQualityVariantProvider = Future<List<XmoVideoQualityVariant>>
    Function(
  XmoVideoQualitySource source,
);

typedef XmoVideoSourceNormalizer = Future<XmoVideoQualityVariant?> Function(
  XmoVideoQualitySource source,
);

class XmoVideoQualitySource {
  const XmoVideoQualitySource({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.durationMs,
    this.isCancelled,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int? durationMs;
  final bool Function()? isCancelled;
}

class XmoVideoQualityVariant {
  const XmoVideoQualityVariant({
    required this.name,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class XmoChunkedMediaUploadService {
  const XmoChunkedMediaUploadService({
    MatrixEncryptedMediaHelper encryptedMediaHelper =
        const MatrixEncryptedMediaHelper(),
    this.chunkSize = defaultChunkSize,
    this.thresholdBytes = defaultThresholdBytes,
    this.qualityVariantProvider,
    this.sourceNormalizer,
  })  : assert(chunkSize > 0),
        assert(thresholdBytes > 0),
        _encryptedMediaHelper = encryptedMediaHelper;

  static const int defaultChunkSize = 4 * 1024 * 1024;
  static const int defaultThresholdBytes = 16 * 1024 * 1024;

  final MatrixEncryptedMediaHelper _encryptedMediaHelper;
  final int chunkSize;
  final int thresholdBytes;
  final XmoVideoQualityVariantProvider? qualityVariantProvider;
  final XmoVideoSourceNormalizer? sourceNormalizer;

  bool shouldUploadAsStream({
    required int size,
    required String mimeType,
  }) {
    return size >= thresholdBytes &&
        mimeType.toLowerCase().startsWith('video/');
  }

  Future<XmoStreamManifest> uploadVideoStream({
    required Uint8List videoBytes,
    required String videoFileName,
    required String videoMimeType,
    required int? durationMs,
    required XmoEncryptedChunkUploader uploadChunk,
    bool Function()? isCancelled,
  }) async {
    if (videoBytes.isEmpty) {
      throw ArgumentError.value(videoBytes.length, 'videoBytes');
    }

    final qualities = <String, XmoStreamQuality>{};
    final sourceVariant = XmoVideoQualityVariant(
      name: 'source',
      bytes: videoBytes,
      fileName: videoFileName,
      mimeType: videoMimeType,
    );
    qualities['source'] = await _uploadQuality(
      sourceVariant,
      uploadChunk: uploadChunk,
      isCancelled: isCancelled,
    );

    final provider = qualityVariantProvider;
    if (provider != null) {
      final variants = await _loadQualityVariants(
        provider,
        XmoVideoQualitySource(
          bytes: videoBytes,
          fileName: videoFileName,
          mimeType: videoMimeType,
          durationMs: durationMs,
          isCancelled: isCancelled,
        ),
        isCancelled,
      );
      for (final variant in variants) {
        _throwIfCancelled(isCancelled);
        final qualityName = _normalizedQualityName(variant.name);
        if (qualityName == 'source' || qualities.containsKey(qualityName)) {
          continue;
        }
        if (variant.bytes.isEmpty ||
            variant.bytes.length >= videoBytes.length) {
          continue;
        }
        try {
          qualities[qualityName] = await _uploadQuality(
            XmoVideoQualityVariant(
              name: qualityName,
              bytes: variant.bytes,
              fileName: variant.fileName,
              mimeType: variant.mimeType,
            ),
            uploadChunk: uploadChunk,
            isCancelled: isCancelled,
          );
        } on XmoChunkedMediaUploadCancelledException {
          rethrow;
        } catch (_) {
          continue;
        }
      }
    }

    return XmoStreamManifest(
      version: XmoStreamManifest.supportedVersion,
      mimeType: videoMimeType,
      size: videoBytes.length,
      chunkSize: chunkSize,
      durationMs: durationMs != null && durationMs > 0 ? durationMs : null,
      qualities: qualities,
    );
  }

  Future<XmoVideoQualityVariant?> normalizeVideoSource({
    required Uint8List videoBytes,
    required String videoFileName,
    required String videoMimeType,
    required int? durationMs,
    bool Function()? isCancelled,
  }) async {
    final normalizer = sourceNormalizer;
    if (normalizer == null ||
        videoBytes.isEmpty ||
        !videoMimeType.toLowerCase().startsWith('video/')) {
      return null;
    }

    try {
      _throwIfCancelled(isCancelled);
      final normalized = await normalizer(
        XmoVideoQualitySource(
          bytes: videoBytes,
          fileName: videoFileName,
          mimeType: videoMimeType,
          durationMs: durationMs,
          isCancelled: isCancelled,
        ),
      );
      _throwIfCancelled(isCancelled);
      if (normalized == null ||
          normalized.bytes.isEmpty ||
          normalized.bytes.length >= videoBytes.length) {
        return null;
      }
      return normalized;
    } on XmoChunkedMediaUploadCancelledException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<List<XmoVideoQualityVariant>> _loadQualityVariants(
    XmoVideoQualityVariantProvider provider,
    XmoVideoQualitySource source,
    bool Function()? isCancelled,
  ) async {
    try {
      _throwIfCancelled(isCancelled);
      final variants = await provider(source);
      _throwIfCancelled(isCancelled);
      return variants;
    } on XmoChunkedMediaUploadCancelledException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  Future<XmoStreamQuality> _uploadQuality(
    XmoVideoQualityVariant variant, {
    required XmoEncryptedChunkUploader uploadChunk,
    required bool Function()? isCancelled,
  }) async {
    final chunks = <XmoStreamChunk>[];
    final chunkCount = (variant.bytes.length / chunkSize).ceil();
    for (var index = 0; index < chunkCount; index++) {
      _throwIfCancelled(isCancelled);
      final start = index * chunkSize;
      final end = min(start + chunkSize, variant.bytes.length);
      final clearChunk = Uint8List.sublistView(variant.bytes, start, end);
      final encrypted = await _encryptedMediaHelper.encrypt(clearChunk);
      _throwIfCancelled(isCancelled);

      final uri = await uploadChunk(
        encryptedBytes: encrypted.data,
        fileName: _chunkFileName(variant.fileName, variant.name, index),
        contentType: 'application/octet-stream',
        chunkIndex: index,
      );
      _throwIfCancelled(isCancelled);

      chunks.add(
        XmoStreamChunk(
          index: index,
          url: uri.toString(),
          key: encrypted.k,
          iv: encrypted.iv,
          sha256: encrypted.sha256,
        ),
      );
    }

    return XmoStreamQuality(
      size: variant.name == 'source' ? null : variant.bytes.length,
      chunkSize: variant.name == 'source' ? null : chunkSize,
      mimeType: variant.name == 'source' ? null : variant.mimeType,
      chunks: chunks,
    );
  }

  String _chunkFileName(String videoFileName, String quality, int index) {
    final safeName = videoFileName.trim().isEmpty ? 'video' : videoFileName;
    return '$safeName.xmo-stream.$quality.$index.chunk';
  }

  String _normalizedQualityName(String quality) {
    return quality.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw const XmoChunkedMediaUploadCancelledException();
    }
  }
}

class XmoChunkedMediaUploadCancelledException implements Exception {
  const XmoChunkedMediaUploadCancelledException();

  @override
  String toString() => 'Chunked media upload cancelled';
}
