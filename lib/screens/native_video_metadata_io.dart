import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class NativeVideoMetadata {
  final int? width;
  final int? height;
  final int? durationMs;

  const NativeVideoMetadata({
    this.width,
    this.height,
    this.durationMs,
  });
}

Future<NativeVideoMetadata?> readNativeVideoMetadata(List<int> videoBytes) async {
  if (videoBytes.isEmpty) return null;

  File? tempFile;
  VideoPlayerController? controller;
  try {
    final tempDir = await getTemporaryDirectory();
    tempFile = File(
      '${tempDir.path}/xmo_video_meta_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    await tempFile.writeAsBytes(videoBytes, flush: true);

    controller = VideoPlayerController.file(tempFile);
    await controller.initialize();

    final size = controller.value.size;
    final duration = controller.value.duration;
    final width = size.width > 0 ? size.width.round() : null;
    final height = size.height > 0 ? size.height.round() : null;

    if (width == null && height == null && duration == Duration.zero) {
      return null;
    }

    return NativeVideoMetadata(
      width: width,
      height: height,
      durationMs: duration == Duration.zero ? null : duration.inMilliseconds,
    );
  } catch (e) {
    debugPrint('[VideoMeta] Failed to read video metadata: $e');
    return null;
  } finally {
    await controller?.dispose();
    if (tempFile != null && await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }
}
