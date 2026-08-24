// Web video view – migrated from deprecated `dart:html` to `package:web`.
//
// This file is only imported on the web (via conditional import with
// `dart.library.js_interop`).  It provides:
//   • registerVideoView / registerVideoUrlView   – embed HTML5 <video>
//   • createVideoView                             – Flutter HtmlElementView
//   • generateVideoThumbnail                      – canvas-based frame grab
//   • disposeVideoView                            – blob cleanup

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

// ignore: undefined_prefixed_name
import 'dart:ui_web' as ui;

final Map<String, String> _blobUrls = {};

// ═══════════════════════════════════════════════════════════════════════════════
// VIDEO ELEMENT REGISTRATION (for inline playback)
// ═══════════════════════════════════════════════════════════════════════════════

/// Registers an HTML5 video element from raw bytes.
void registerVideoView(String viewId, Uint8List bytes, String mimeType) {
  final jsArray = bytes.toJS;
  final blob = web.Blob([jsArray].toJS, web.BlobPropertyBag(type: mimeType));
  final blobUrl = web.URL.createObjectURL(blob);
  _blobUrls[viewId] = blobUrl;
  _registerVideoElement(viewId, blobUrl);
}

/// Registers an HTML5 video element that streams from an existing URL.
void registerVideoUrlView(String viewId, String url) {
  _registerVideoElement(viewId, url);
}

void _registerVideoElement(String viewId, String src) {
  ui.platformViewRegistry.registerViewFactory(viewId, (int id) {
    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..src = src
      ..autoplay = true
      ..controls = true;
    video.style.width = '100%';
    video.style.height = '100%';
    video.style.objectFit = 'contain';
    video.style.backgroundColor = '#0B1014';
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
    web.URL.revokeObjectURL(url);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIDEO THUMBNAIL GENERATION (canvas-based frame grab)
// ═══════════════════════════════════════════════════════════════════════════════

/// Generates a thumbnail from video bytes by extracting a frame at ~1 second.
/// Uses a hidden HTML5 <video> + <canvas> to capture the frame as JPEG.
Future<Uint8List?> generateVideoThumbnail(
  Uint8List videoBytes,
  String mimeType,
) async {
  final completer = Completer<Uint8List?>();
  bool completed = false;

  void finish(Uint8List? result) {
    if (!completed) {
      completed = true;
      completer.complete(result);
    }
  }

  Uint8List? captureFrame(web.HTMLVideoElement video) {
    try {
      final vw = video.videoWidth > 0 ? video.videoWidth : 480;
      final vh = video.videoHeight > 0 ? video.videoHeight : 270;
      final scale = (480 / vw).clamp(0.1, 1.0);
      final width = (vw * scale).round();
      final height = (vh * scale).round();

      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement;
      canvas.width = width;
      canvas.height = height;

      final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
      ctx.drawImage(video, 0, 0, width.toDouble(), height.toDouble());

      final dataUrl = canvas.toDataURL('image/jpeg', 0.92.toJS);
      final base64Data = dataUrl.split(',').last;
      final bytes = base64Decode(base64Data);
      return bytes.isNotEmpty ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
  }

  try {
    final jsArray = videoBytes.toJS;
    final blob = web.Blob([jsArray].toJS, web.BlobPropertyBag(type: mimeType));
    final blobUrl = web.URL.createObjectURL(blob);

    final video = web.document.createElement('video') as web.HTMLVideoElement;
    video.src = blobUrl;
    video.muted = true;
    video.preload = 'auto';
    video.style.position = 'fixed';
    video.style.left = '-9999px';
    video.style.top = '-9999px';
    video.style.width = '480px';
    video.style.height = '270px';

    web.document.body?.append(video);

    void cleanup() {
      video.pause();
      video.remove();
      web.URL.revokeObjectURL(blobUrl);
    }

    // onLoadedData: frame data is ready, seek to 1s (or 0 for short clips)
    video.onloadeddata = ((web.Event e) {
      final seekTo = video.duration.isFinite && video.duration > 1.5
          ? 1.0
          : 0.0;
      video.currentTime = seekTo;
    }).toJS;

    // onSeeked: capture the frame after seeking
    video.onseeked = ((web.Event e) {
      final result = captureFrame(video);
      cleanup();
      finish(result);
    }).toJS;

    // Fallback: onCanPlay fires earlier — capture at whatever time is ready
    video.oncanplay = ((web.Event e) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!completed) {
          final result = captureFrame(video);
          cleanup();
          finish(result);
        }
      });
    }).toJS;

    // Error handler
    video.onerror = ((web.Event e) {
      cleanup();
      finish(null);
    }).toJS;

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
