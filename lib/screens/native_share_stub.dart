import 'dart:typed_data';

Future<void> shareFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  throw UnsupportedError('Sharing files is not supported on this platform');
}

Future<void> openFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  throw UnsupportedError('Opening files is not supported on this platform');
}
