import 'dart:typed_data';

import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createNativeVideoController({
  required Uint8List bytes,
  required String mimeType,
  required String title,
}) async {
  throw UnsupportedError('Native video playback is not used on web.');
}
