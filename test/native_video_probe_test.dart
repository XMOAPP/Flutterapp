import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/native_video_probe_io.dart';

void main() {
  test('only AVC with AAC or no audio bypasses normalization', () {
    const compatible = NativeVideoProbeResult(
      videoMimeType: 'video/avc',
      audioMimeType: 'audio/mp4a-latm',
    );
    const silent = NativeVideoProbeResult(videoMimeType: 'video/avc');
    const hevc = NativeVideoProbeResult(
      videoMimeType: 'video/hevc',
      audioMimeType: 'audio/mp4a-latm',
    );
    const unsupportedAudio = NativeVideoProbeResult(
      videoMimeType: 'video/avc',
      audioMimeType: 'audio/opus',
    );

    expect(compatible.isMatrixCompatibleMp4, isTrue);
    expect(silent.isMatrixCompatibleMp4, isTrue);
    expect(hevc.isMatrixCompatibleMp4, isFalse);
    expect(unsupportedAudio.isMatrixCompatibleMp4, isFalse);
  });
}
