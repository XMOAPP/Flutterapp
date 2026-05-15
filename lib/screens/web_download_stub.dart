import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

/// Native implementation for Android/iOS.
///
/// Files are saved into the app-specific external/documents directory so this
/// works without broad storage permissions on modern Android.
Future<String> downloadFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  if (bytes.isEmpty) {
    throw Exception('File is empty');
  }

  final baseDir =
      Platform.isAndroid ? await getExternalStorageDirectory() : null;
  final directory = Directory(
    '${(baseDir ?? await getApplicationDocumentsDirectory()).path}/XMO Downloads',
  );
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final safeName = _safeFileName(fileName);
  var file = File('${directory.path}/$safeName');
  if (await file.exists()) {
    final dot = safeName.lastIndexOf('.');
    final name = dot > 0 ? safeName.substring(0, dot) : safeName;
    final ext = dot > 0 ? safeName.substring(dot) : '';
    file = File(
      '${directory.path}/${name}_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
  }

  await file.writeAsBytes(bytes, flush: true);
  try {
    await _saveToAndroidGalleryIfMedia(
      filePath: file.path,
      fileName: safeName,
      mimeType: mimeType ?? lookupMimeType(safeName, headerBytes: bytes),
    );
  } catch (e) {
    debugPrint('[Download] Saved to app folder, but gallery copy failed: $e');
  }
  return file.path;
}

/// Kept for API parity with the web helper. Native video playback is handled by
/// the Flutter fullscreen video player.
Future<void> playVideo(Uint8List bytes, String mimeType) async {}

Future<void> _saveToAndroidGalleryIfMedia({
  required String filePath,
  required String fileName,
  required String? mimeType,
}) async {
  if (!Platform.isAndroid || mimeType == null) return;
  if (!mimeType.startsWith('image/') && !mimeType.startsWith('video/')) return;

  const channel = MethodChannel('com.xmo.xmo/media_store');
  await channel.invokeMethod<void>('saveMediaToGallery', {
    'filePath': filePath,
    'fileName': fileName,
    'mimeType': mimeType,
  });
}

String _safeFileName(String value) {
  final trimmed = value.trim().isEmpty ? 'xmo_file' : value.trim();
  return trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
}
