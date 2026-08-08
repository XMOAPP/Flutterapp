import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import 'xmo_chunked_media_upload_service.dart';

XmoVideoQualityVariantProvider? createVideoCompressionQualityVariantProvider() {
  return const NativeVideoCompressionQualityVariantProvider().call;
}

XmoVideoSourceNormalizer? createVideoCompressionSourceNormalizer() {
  return const NativeVideoCompressionQualityVariantProvider().normalizeSource;
}

class NativeVideoCompressionQualityVariantProvider {
  const NativeVideoCompressionQualityVariantProvider();

  Future<XmoVideoQualityVariant?> normalizeSource(
    XmoVideoQualitySource source,
  ) async {
    _throwIfCancelled(source);
    if (!source.mimeType.toLowerCase().startsWith('video/')) {
      return null;
    }

    final workDir = await _createWorkDir();
    final providedSourcePath = source.sourcePath;
    final sourceFile = providedSourcePath != null
        ? File(providedSourcePath)
        : File(_joinPath(workDir.path, _safeFileName(source.fileName)));
    final ownsSourceFile = providedSourcePath == null;
    File? normalizedFile;

    try {
      if (ownsSourceFile) {
        await sourceFile.writeAsBytes(source.bytes, flush: true);
      }
      _throwIfCancelled(source);

      final info = await _compressWithCancellation(
        sourceFile.path,
        VideoQuality.DefaultQuality,
        source,
      );
      _throwIfCancelled(source);
      normalizedFile = _mediaInfoFile(info);
      if (normalizedFile == null || !await normalizedFile.exists()) {
        return null;
      }

      final normalizedBytes = await normalizedFile.readAsBytes();
      if (normalizedBytes.isEmpty ||
          normalizedBytes.length >= source.bytes.length) {
        return null;
      }

      return XmoVideoQualityVariant(
        name: 'source',
        bytes: Uint8List.fromList(normalizedBytes),
        fileName: _normalizedSourceFileName(source.fileName),
        mimeType: 'video/mp4',
      );
    } on XmoChunkedMediaUploadCancelledException {
      await VideoCompress.cancelCompression();
      rethrow;
    } finally {
      if (ownsSourceFile) await _deleteQuietly(sourceFile);
      if (normalizedFile != null) {
        await _deleteQuietly(normalizedFile);
      }
      await _deleteDirectoryQuietly(workDir);
      await VideoCompress.deleteAllCache();
    }
  }

  Future<List<XmoVideoQualityVariant>> call(
    XmoVideoQualitySource source,
  ) async {
    _throwIfCancelled(source);
    if (!source.mimeType.toLowerCase().startsWith('video/')) {
      return const [];
    }

    final workDir = await _createWorkDir();
    final providedSourcePath = source.sourcePath;
    final sourceFile = providedSourcePath != null
        ? File(providedSourcePath)
        : File(_joinPath(workDir.path, _safeFileName(source.fileName)));
    final ownsSourceFile = providedSourcePath == null;
    final variants = <XmoVideoQualityVariant>[];
    final compressedFiles = <File>[];

    try {
      if (ownsSourceFile) {
        await sourceFile.writeAsBytes(source.bytes, flush: true);
      }
      _throwIfCancelled(source);

      final requests = <_CompressionRequest>[
        const _CompressionRequest(
          name: '480p',
          quality: VideoQuality.Res640x480Quality,
          fileSuffix: '480p',
        ),
        const _CompressionRequest(
          name: '240p',
          quality: VideoQuality.LowQuality,
          fileSuffix: '240p',
        ),
      ];

      for (final request in requests) {
        _throwIfCancelled(source);
        final info = await _compressWithCancellation(
          sourceFile.path,
          request.quality,
          source,
        );
        _throwIfCancelled(source);
        final compressed = _mediaInfoFile(info);
        if (compressed == null || !await compressed.exists()) {
          continue;
        }
        compressedFiles.add(compressed);

        final bytes = await compressed.readAsBytes();
        if (bytes.isEmpty || bytes.length >= source.bytes.length) {
          continue;
        }
        variants.add(
          XmoVideoQualityVariant(
            name: request.name,
            bytes: Uint8List.fromList(bytes),
            fileName: _variantFileName(source.fileName, request.fileSuffix),
            mimeType: 'video/mp4',
          ),
        );
      }
      return variants;
    } on XmoChunkedMediaUploadCancelledException {
      await VideoCompress.cancelCompression();
      rethrow;
    } finally {
      if (ownsSourceFile) await _deleteQuietly(sourceFile);
      for (final file in compressedFiles) {
        await _deleteQuietly(file);
      }
      await _deleteDirectoryQuietly(workDir);
      await VideoCompress.deleteAllCache();
    }
  }

  Future<Directory> _createWorkDir() async {
    final tempRoot = await getTemporaryDirectory();
    final millis = DateTime.now().millisecondsSinceEpoch;
    return Directory(_joinPath(
      _joinPath(tempRoot.path, 'xmo_video_compress'),
      '$millis',
    )).create(recursive: true);
  }

  Future<MediaInfo?> _compressWithCancellation(
    String sourcePath,
    VideoQuality quality,
    XmoVideoQualitySource source,
  ) async {
    final completer = Completer<MediaInfo?>();
    unawaited(
      VideoCompress.compressVideo(
        sourcePath,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
      ).then((value) {
        if (!completer.isCompleted) completer.complete(value);
      }).catchError((Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }),
    );

    while (!completer.isCompleted) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (source.isCancelled?.call() ?? false) {
        await VideoCompress.cancelCompression();
        throw const XmoChunkedMediaUploadCancelledException();
      }
    }
    return completer.future;
  }

  File? _mediaInfoFile(MediaInfo? info) {
    if (info == null) return null;
    final file = info.file;
    if (file != null) return file;
    final path = info.path;
    if (path == null || path.trim().isEmpty) return null;
    return File(path);
  }

  String _safeFileName(String fileName) {
    final cleaned = fileName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    return cleaned.isEmpty ? 'video.mp4' : cleaned;
  }

  String _variantFileName(String fileName, String suffix) {
    final safeName = _safeFileName(fileName);
    final dotIndex = safeName.lastIndexOf('.');
    final basename = dotIndex <= 0 ? safeName : safeName.substring(0, dotIndex);
    return '$basename.$suffix.mp4';
  }

  String _normalizedSourceFileName(String fileName) {
    final safeName = _safeFileName(fileName);
    final dotIndex = safeName.lastIndexOf('.');
    final basename = dotIndex <= 0 ? safeName : safeName.substring(0, dotIndex);
    return '$basename.mp4';
  }

  String _joinPath(String first, String second) {
    final separator = Platform.pathSeparator;
    if (first.endsWith(separator)) return '$first$second';
    return '$first$separator$second';
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _deleteDirectoryQuietly(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  void _throwIfCancelled(XmoVideoQualitySource source) {
    if (source.isCancelled?.call() ?? false) {
      throw const XmoChunkedMediaUploadCancelledException();
    }
  }
}

class _CompressionRequest {
  const _CompressionRequest({
    required this.name,
    required this.quality,
    required this.fileSuffix,
  });

  final String name;
  final VideoQuality quality;
  final String fileSuffix;
}
