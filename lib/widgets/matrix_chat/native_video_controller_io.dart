import 'dart:io';

import 'package:flutter/foundation.dart';
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

  final controller = await _initializeController(
    () => VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      viewType: _preferredVideoViewType,
    ),
    fallbackFactory: () => VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    ),
  );
  await controller.play();
  return controller;
}

Future<VideoPlayerController> createNativeNetworkVideoController({
  required Uri url,
  required Map<String, String> headers,
}) async {
  final controller = await _initializeController(
    () => VideoPlayerController.networkUrl(
      url,
      httpHeaders: headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      viewType: _preferredVideoViewType,
    ),
    fallbackFactory: () => VideoPlayerController.networkUrl(
      url,
      httpHeaders: headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    ),
  );
  await controller.play();
  return controller;
}

VideoViewType get _preferredVideoViewType {
  return defaultTargetPlatform == TargetPlatform.android
      ? VideoViewType.platformView
      : VideoViewType.textureView;
}

Future<VideoPlayerController> _initializeController(
  VideoPlayerController Function() factory, {
  required VideoPlayerController Function() fallbackFactory,
}) async {
  final controller = factory();
  try {
    await controller.initialize();
    return controller;
  } catch (_) {
    await controller.dispose();
    final fallbackController = fallbackFactory();
    await fallbackController.initialize();
    return fallbackController;
  }
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
