class NativeVideoMetadata {
  final int? width;
  final int? height;
  final int? durationMs;

  const NativeVideoMetadata({this.width, this.height, this.durationMs});
}

Future<NativeVideoMetadata?> readNativeVideoMetadata(
  List<int> videoBytes,
) async {
  return null;
}

Future<NativeVideoMetadata?> readNativeVideoMetadataFromPath(
  String videoPath,
) async => null;
