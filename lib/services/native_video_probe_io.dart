import 'package:flutter/services.dart';

class NativeVideoProbeResult {
  const NativeVideoProbeResult({
    required this.videoMimeType,
    this.audioMimeType,
    this.width,
    this.height,
    this.durationMs,
  });

  final String videoMimeType;
  final String? audioMimeType;
  final int? width;
  final int? height;
  final int? durationMs;

  bool get isMatrixCompatibleMp4 {
    final video = videoMimeType.toLowerCase();
    final audio = audioMimeType?.toLowerCase();
    return video == 'video/avc' &&
        (audio == null || audio == 'audio/mp4a-latm');
  }
}

Future<NativeVideoProbeResult?> probeNativeVideo(String path) async {
  if (path.trim().isEmpty) return null;
  try {
    const channel = MethodChannel('com.xmo.xmo/media_store');
    final raw = await channel.invokeMapMethod<String, dynamic>('probeVideo', {
      'filePath': path,
    });
    final videoMimeType = raw?['videoMimeType']?.toString();
    if (videoMimeType == null || videoMimeType.isEmpty) return null;
    return NativeVideoProbeResult(
      videoMimeType: videoMimeType,
      audioMimeType: raw?['audioMimeType']?.toString(),
      width: (raw?['width'] as num?)?.toInt(),
      height: (raw?['height'] as num?)?.toInt(),
      durationMs: (raw?['durationMs'] as num?)?.toInt(),
    );
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
