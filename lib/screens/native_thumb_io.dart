import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// Native implementation — writes bytes to a temp file, extracts a frame,
// then deletes the temp file. Uses the video_thumbnail plugin.
Future<Uint8List?> generateNativeThumbnail(Uint8List videoBytes) async {
  if (videoBytes.isEmpty) return null;

  File? tempFile;
  try {
    final tempDir = await getTemporaryDirectory();
    tempFile = File(
      '${tempDir.path}/xmo_thumb_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    await tempFile.writeAsBytes(videoBytes, flush: true);

    return await VideoThumbnail.thumbnailData(
      video: tempFile.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 720,
      timeMs: 1000,
      quality: 75,
    );
  } catch (e) {
    debugPrint('[NativeThumb] Failed to generate thumbnail: $e');
    return null;
  } finally {
    if (tempFile != null && await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }
}
