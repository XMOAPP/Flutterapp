import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readAudioFileBytes(String path) {
  return File(path).readAsBytes();
}
