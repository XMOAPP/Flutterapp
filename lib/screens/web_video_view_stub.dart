import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Stub — returns an empty widget on non-web platforms.
Widget createVideoView(Uint8List bytes, String mimeType, String viewId) {
  return const Center(child: Text('Video not supported on this platform'));
}

/// Stub — no-op on non-web.
void registerVideoView(String viewId, Uint8List bytes, String mimeType) {}

/// Stub - no-op on non-web.
void registerVideoUrlView(String viewId, String url) {}

/// Stub - no-op on non-web.
void disposeVideoView(String viewId) {}

/// Stub — returns null on non-web platforms.
Future<Uint8List?> generateVideoThumbnail(
    Uint8List videoBytes, String mimeType) async {
  return null;
}
