// Web-only file download and video playback helpers.
// Migrated from deprecated dart:html to package:web + dart:js_interop.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of the given bytes as a file.
Future<String> downloadFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  final jsArray = bytes.toJS;
  final blob = web.Blob([jsArray].toJS);
  final url = web.URL.createObjectURL(blob);

  final anchor =
      web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  anchor.style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return fileName;
}

/// Opens a video blob URL in a new browser tab for in-app playback.
Future<void> playVideo(Uint8List bytes, String mimeType) async {
  final jsArray = bytes.toJS;
  final blob = web.Blob([jsArray].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  // Revoke after a delay so the tab has time to load
  Future.delayed(const Duration(seconds: 10), () {
    web.URL.revokeObjectURL(url);
  });
}
