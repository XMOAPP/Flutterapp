import 'dart:io';
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
  String? storageCategory,
}) async {
  if (bytes.isEmpty) {
    throw Exception('File is empty');
  }

  final resolvedMimeType =
      mimeType ?? lookupMimeType(fileName, headerBytes: bytes);
  final safeName = _safeFileName(fileName);
  if (Platform.isAndroid &&
      (resolvedMimeType?.startsWith('image/') == true ||
          resolvedMimeType?.startsWith('video/') == true)) {
    const channel = MethodChannel('com.xmo.xmo/media_store');
    final uri = await channel.invokeMethod<String>('saveMediaBytesToGallery', {
      'bytes': bytes,
      'fileName': safeName,
      'mimeType': resolvedMimeType,
    });
    if (uri == null || uri.isEmpty) {
      throw Exception('Gallery did not return the saved media location');
    }
    return uri;
  }

  final baseDir = Platform.isAndroid
      ? await getExternalStorageDirectory()
      : null;
  final rootDirectory = Directory(
    '${(baseDir ?? await getApplicationDocumentsDirectory()).path}/XMO Downloads',
  );
  final folder = _safeFolderName(storageCategory);
  final directory = folder == null
      ? rootDirectory
      : Directory('${rootDirectory.path}/$folder');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

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
  return file.path;
}

/// Kept for API parity with the web helper. Native video playback is handled by
/// the Flutter fullscreen video player.
Future<void> playVideo(Uint8List bytes, String mimeType) async {}

String _safeFileName(String value) {
  final trimmed = value.trim().isEmpty ? 'xmo_file' : value.trim();
  return trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
}

String? _safeFolderName(String? value) {
  switch (value) {
    case 'videos':
      return 'Videos';
    case 'audio':
      return 'Audio';
    case 'photos':
      return 'Photos';
    case 'files':
      return 'Files';
  }
  return null;
}
