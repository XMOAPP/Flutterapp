// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:typed_data';
// ignore: undefined_prefixed_name
import 'dart:ui_web' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';

final Map<String, String> _blobUrls = {};

/// Registers an HTML5 video element with the given viewId.
void registerVideoView(String viewId, Uint8List bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);
  _blobUrls[viewId] = blobUrl;

  _registerVideoElement(viewId, blobUrl);
}

/// Registers an HTML5 video element that streams from an existing URL.
void registerVideoUrlView(String viewId, String url) {
  _registerVideoElement(viewId, url);
}

void _registerVideoElement(String viewId, String src) {
  ui.platformViewRegistry.registerViewFactory(viewId, (int id) {
    final video = html.VideoElement()
      ..src = src
      ..autoplay = true
      ..controls = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000000';
    return video;
  });
}

/// Creates a Flutter widget that embeds the HTML video.
Widget createVideoView(Uint8List bytes, String mimeType, String viewId) {
  return HtmlElementView(viewType: viewId);
}

/// Cleans up the blob URL for the given viewId.
void disposeVideoView(String viewId) {
  final url = _blobUrls.remove(viewId);
  if (url != null) {
    html.Url.revokeObjectUrl(url);
  }
}

/// Generates a thumbnail from video bytes by extracting a frame at ~1 second.
/// Uses a hidden HTML5 <video> + <canvas> to capture the frame as JPEG (compressed).
Future<Uint8List?> generateVideoThumbnail(Uint8List videoBytes, String mimeType) async {
  final completer = Completer<Uint8List?>();
  bool completed = false;

  void finish(Uint8List? result) {
    if (!completed) {
      completed = true;
      completer.complete(result);
    }
  }

  Uint8List? captureFrame(html.VideoElement video) {
    try {
      final vw = video.videoWidth > 0 ? video.videoWidth : 480;
      final vh = video.videoHeight > 0 ? video.videoHeight : 270;
      final scale = (480 / vw).clamp(0.1, 1.0);
      final width = (vw * scale).round();
      final height = (vh * scale).round();

      final canvas = html.CanvasElement(width: width, height: height);
      final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D;
      ctx.drawImageScaled(video, 0, 0, width, height);

      final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
      final base64Data = dataUrl.split(',').last;
      final bytes = base64Decode(base64Data);
      return bytes.isNotEmpty ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
  }

  try {
    final blob = html.Blob([videoBytes], mimeType);
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);

    final video = html.VideoElement()
      ..src = blobUrl
      ..muted = true
      ..preload = 'auto'
      ..style.position = 'fixed'
      ..style.left = '-9999px'
      ..style.top = '-9999px'
      ..style.width = '480px'
      ..style.height = '270px';

    html.document.body?.append(video);

    void cleanup() {
      video.pause();
      video.remove();
      html.Url.revokeObjectUrl(blobUrl);
    }

    // onLoadedData: frame data is ready, seek to 1s (or 0 for short clips)
    video.onLoadedData.first.then((_) {
      final seekTo = video.duration.isFinite && video.duration > 1.5 ? 1.0 : 0.0;
      video.currentTime = seekTo;
    });

    // onSeeked: capture the frame
    video.onSeeked.first.then((_) {
      final result = captureFrame(video);
      cleanup();
      finish(result);
    });

    // Fallback: onCanPlay fires earlier — capture at whatever time is ready
    video.onCanPlay.first.then((_) async {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!completed) {
        final result = captureFrame(video);
        cleanup();
        finish(result);
      }
    });

    // Error handler
    video.onError.first.then((_) {
      cleanup();
      finish(null);
    });

    // Hard timeout — 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (!completed) {
        cleanup();
        finish(null);
      }
    });

    video.load();
  } catch (e) {
    finish(null);
  }

  return completer.future;
}
