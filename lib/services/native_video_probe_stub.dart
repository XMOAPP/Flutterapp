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

  bool get isMatrixCompatibleMp4 => false;
}

Future<NativeVideoProbeResult?> probeNativeVideo(String path) async => null;
