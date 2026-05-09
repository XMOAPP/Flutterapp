import 'dart:typed_data';

/// Stub implementation for non-web platforms.
void downloadFile(Uint8List bytes, String fileName) {
  throw UnsupportedError('File download not supported on this platform');
}

/// Stub implementation for non-web platforms.
void playVideo(Uint8List bytes, String mimeType) {
  throw UnsupportedError('Video playback not supported on this platform');
}
