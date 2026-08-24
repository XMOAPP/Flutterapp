import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

Future<void> shareFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  if (bytes.isEmpty) {
    throw Exception('File is empty');
  }

  final directory = await _sharedTempDirectory();
  final resolvedMimeType =
      mimeType ?? lookupMimeType(fileName, headerBytes: bytes);
  final safeName = _safeFileName(
    _ensureFileExtension(fileName, resolvedMimeType),
  );
  final file = File('${directory.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);

  const channel = MethodChannel('com.xmo.xmo/media_store');
  await channel.invokeMethod<void>('shareFile', {
    'filePath': file.path,
    'fileName': safeName,
    'mimeType':
        resolvedMimeType ?? lookupMimeType(safeName, headerBytes: bytes),
  });
}

Future<void> openFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  if (bytes.isEmpty) {
    throw Exception('File is empty');
  }

  final directory = await _sharedTempDirectory();
  final resolvedMimeType =
      mimeType ?? lookupMimeType(fileName, headerBytes: bytes);
  final safeName = _safeFileName(
    _ensureFileExtension(fileName, resolvedMimeType),
  );
  final file = File('${directory.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);

  const channel = MethodChannel('com.xmo.xmo/media_store');
  await channel.invokeMethod<void>('openFile', {
    'filePath': file.path,
    'fileName': safeName,
    'mimeType':
        resolvedMimeType ??
        lookupMimeType(safeName, headerBytes: bytes) ??
        '*/*',
  });
}

String _ensureFileExtension(String fileName, String? mimeType) {
  final trimmed = fileName.trim();
  final fallbackBase = trimmed.isEmpty ? 'xmo_file' : trimmed;
  final dotIndex = fallbackBase.lastIndexOf('.');
  final hasUsableExtension = dotIndex > 0 && dotIndex < fallbackBase.length - 1;
  if (hasUsableExtension) return fallbackBase;

  final extension = _fileExtensionForMime(mimeType);
  if (extension == null || extension.isEmpty) return fallbackBase;
  return '$fallbackBase.$extension';
}

String? _fileExtensionForMime(String? mimeType) {
  switch ((mimeType ?? '').toLowerCase()) {
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    case 'video/mp4':
      return 'mp4';
    case 'video/quicktime':
      return 'mov';
    case 'video/webm':
      return 'webm';
    case 'audio/mpeg':
      return 'mp3';
    case 'audio/mp4':
    case 'audio/aac':
      return 'm4a';
    case 'audio/ogg':
      return 'ogg';
    case 'application/pdf':
      return 'pdf';
    default:
      return null;
  }
}

String _safeFileName(String value) {
  final trimmed = value.trim().isEmpty ? 'xmo_file' : value.trim();
  return trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
}

Future<Directory> _sharedTempDirectory() async {
  final temporaryDirectory = await getTemporaryDirectory();
  final directory = Directory('${temporaryDirectory.path}/xmo_shared');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}
