import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createNativeVideoController({
  required Uint8List bytes,
  required String mimeType,
  required String title,
}) async {
  if (bytes.isEmpty) {
    throw Exception('Video file is empty');
  }

  final tempDir = await getTemporaryDirectory();
  final directory = Directory('${tempDir.path}/xmo_video_playback');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final file = File(
    '${directory.path}/${DateTime.now().microsecondsSinceEpoch}${_extensionFor(mimeType, title)}',
  );
  await file.writeAsBytes(bytes, flush: true);

  final controller = VideoPlayerController.file(file);
  await controller.initialize();
  await controller.play();
  return controller;
}

String _extensionFor(String mimeType, String title) {
  final titleDot = title.lastIndexOf('.');
  if (titleDot > 0 && titleDot < title.length - 1) {
    return title.substring(titleDot);
  }

  switch (mimeType.toLowerCase()) {
    case 'video/mp4':
      return '.mp4';
    case 'video/quicktime':
      return '.mov';
    case 'video/webm':
      return '.webm';
    case 'video/x-matroska':
      return '.mkv';
    default:
      return '.mp4';
  }
}
