import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String?> createAudioPlaybackFile({
  required String eventId,
  required Uint8List bytes,
  required String mimeType,
}) async {
  if (bytes.isEmpty) return null;

  final tempDir = await getTemporaryDirectory();
  final directory = Directory('${tempDir.path}/xmo_audio_playback');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final safeEventId = eventId.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  final file = File(
    '${directory.path}/$safeEventId${_extensionForMimeType(mimeType)}',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> deleteAudioPlaybackFile(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Temp playback files are best-effort cleanup.
  }
}

String _extensionForMimeType(String mimeType) {
  final normalized = mimeType.toLowerCase();
  if (normalized.contains('mpeg') || normalized.contains('mp3')) return '.mp3';
  if (normalized.contains('ogg') || normalized.contains('opus')) return '.ogg';
  if (normalized.contains('wav')) return '.wav';
  if (normalized.contains('aac')) return '.aac';
  return '.m4a';
}
