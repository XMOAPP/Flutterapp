import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:matrix/matrix.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import '../../providers/matrix_provider.dart';
import '../../services/matrix_service.dart';
import '../web_video_view_stub.dart'
    if (dart.library.js_interop) '../web_video_view.dart' as web_video;
import '../native_thumb_stub.dart'
    if (dart.library.io) '../native_thumb_io.dart';
import '../native_video_metadata_stub.dart'
    if (dart.library.io) '../native_video_metadata_io.dart';

class MatrixDownloadCancelledException implements Exception {
  const MatrixDownloadCancelledException();

  @override
  String toString() => 'Download cancelled';
}

/// Handles all media-related operations (upload, download, caching)
class MediaHandler {
  final MatrixProvider matrixProvider;
  final BuildContext context;

  // Global in-memory image cache (persists across chat screen navigations)
  static final Map<String, Uint8List> _imageCache = {};
  static final Map<String, Future<Uint8List?>> _imageLoading = {};

  /// Gets the persistent Hive cache box (opened in MatrixService.init)
  static Box<Uint8List>? get _hiveCache {
    return Hive.isBoxOpen('xmo_media_cache')
        ? Hive.box<Uint8List>('xmo_media_cache')
        : null;
  }

  /// Synchronous cache lookup to prevent FutureBuilder flicker.
  /// Checks memory cache first, then falls back to persistent Hive cache.
  static Uint8List? getCachedThumbnail(String eventId) {
    final key = '${eventId}_video_thumb';
    if (_imageCache.containsKey(key)) return _imageCache[key];

    // Check persistent disk cache
    final hiveBytes = _hiveCache?.get(key);
    if (hiveBytes != null) {
      _imageCache[key] = hiveBytes; // Promote to memory
      return hiveBytes;
    }
    return null;
  }

  /// Helper to save to both caches
  static void _cacheThumbnail(String cacheKey, Uint8List bytes) {
    _imageCache[cacheKey] = bytes;
    _hiveCache?.put(cacheKey, bytes);
  }

  static void clearMemoryCache() {
    _imageCache.clear();
    _imageLoading.clear();
  }

  static int get memoryCacheCount => _imageCache.length + _imageLoading.length;

  MediaHandler({
    required this.matrixProvider,
    required this.context,
  });

  /// Creates authenticated download callback for Matrix media
  Future<Uint8List> Function(Uri) authenticatedDownload() {
    return (Uri url) async {
      final request = matrixProvider.service.getMediaRequestForUrl(url);
      debugPrint('[MediaDownload] Fetching: ${request.uri}');
      final response = await http.get(request.uri, headers: request.headers);
      if (response.statusCode != 200) {
        throw Exception(
            'Media download failed: ${response.statusCode} ${response.reasonPhrase}');
      }
      return response.bodyBytes;
    };
  }

  /// Authenticated Matrix media download with chunk progress and cancellation.
  ///
  /// This intentionally exists next to [authenticatedDownload] instead of
  /// replacing it, because thumbnails and inline previews should keep the
  /// stable cached path. Use this for manual user-triggered downloads.
  Future<Uint8List> Function(Uri) authenticatedDownloadWithProgress({
    void Function(int downloadedBytes, int totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) {
    return (Uri url) async {
      final mediaRequest = matrixProvider.service.getMediaRequestForUrl(url);
      debugPrint('[MediaDownload] Streaming: ${mediaRequest.uri}');
      final client = http.Client();
      Timer? cancelTimer;
      try {
        cancelTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
          if (isCancelled?.call() == true) {
            client.close();
          }
        });
        _throwIfDownloadCancelled(isCancelled);
        final request = http.Request('GET', mediaRequest.uri)
          ..headers.addAll(mediaRequest.headers);
        final response = await client.send(request);
        _throwIfDownloadCancelled(isCancelled);

        if (response.statusCode != 200) {
          throw Exception(
            'Media download failed: ${response.statusCode} ${response.reasonPhrase}',
          );
        }

        final totalBytes = response.contentLength ?? 0;
        var downloadedBytes = 0;
        onProgress?.call(0, totalBytes);
        final builder = BytesBuilder(copy: false);

        await for (final chunk in response.stream) {
          _throwIfDownloadCancelled(isCancelled);
          builder.add(chunk);
          downloadedBytes += chunk.length;
          onProgress?.call(downloadedBytes, totalBytes);
        }

        _throwIfDownloadCancelled(isCancelled);
        final bytes = builder.takeBytes();
        onProgress?.call(
            bytes.length, totalBytes > 0 ? totalBytes : bytes.length);
        return bytes;
      } on http.ClientException {
        _throwIfDownloadCancelled(isCancelled);
        rethrow;
      } finally {
        cancelTimer?.cancel();
        client.close();
      }
    };
  }

  void _throwIfDownloadCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw const MatrixDownloadCancelledException();
    }
  }

  /// Downloads image bytes from event with caching
  Future<Uint8List?> loadImageBytes(Event event,
      {bool getThumbnail = false}) async {
    final cacheKey = '${event.eventId}_$getThumbnail';
    if (_imageCache.containsKey(cacheKey)) return _imageCache[cacheKey];
    if (_imageLoading.containsKey(cacheKey)) return _imageLoading[cacheKey];

    final future = () async {
      try {
        debugPrint(
            '[ImageLoad] Loading ${getThumbnail ? "thumbnail" : "full"} for event ${event.eventId}');
        debugPrint(
            '[ImageLoad] Event type: ${event.type}, messageType: ${event.messageType}');
        debugPrint('[ImageLoad] Has thumbnail info: ${event.hasThumbnail}');

        final matrixFile = await event.downloadAndDecryptAttachment(
          getThumbnail: getThumbnail,
          downloadCallback: authenticatedDownload(),
        );
        final bytes = matrixFile.bytes;
        debugPrint('[ImageLoad] Downloaded ${bytes.length} bytes');

        if (bytes.isNotEmpty) {
          _imageCache[cacheKey] = bytes;
          return bytes;
        }
      } catch (e) {
        debugPrint('[ImageLoad] Error downloading attachment: $e');
        // If thumbnail fails, try full image/video
        if (getThumbnail) {
          try {
            debugPrint('[ImageLoad] Thumbnail failed, trying full attachment');
            final matrixFile = await event.downloadAndDecryptAttachment(
              getThumbnail: false,
              downloadCallback: authenticatedDownload(),
            );
            final bytes = matrixFile.bytes;
            if (bytes.isNotEmpty) {
              _imageCache[cacheKey] = bytes;
              return bytes;
            }
          } catch (e2) {
            debugPrint('[ImageLoad] Full attachment also failed: $e2');
          }
        }
      }
      return null;
    }();

    _imageLoading[cacheKey] = future;
    return future;
  }

  /// Downloads partial video bytes (first chunk) for thumbnail generation
  Future<Uint8List?> downloadPartialVideo(Event event,
      {int maxBytes = 2097152}) async {
    try {
      final mxcUrl = event.content['url'] as String?;
      if (mxcUrl == null || !mxcUrl.startsWith('mxc://')) {
        debugPrint('[PartialVideo] Invalid MXC URL');
        return null;
      }

      final mediaRequest = matrixProvider.service.getMediaRequest(mxcUrl);
      if (mediaRequest == null) return null;

      debugPrint(
          '[PartialVideo] Requesting first $maxBytes bytes from: ${mediaRequest.uri}');

      // Make HTTP request with Range header to get only first chunk
      final response = await http.get(
        mediaRequest.uri,
        headers: {
          'Range': 'bytes=0-${maxBytes - 1}', // Request first 2 MB
          ...mediaRequest.headers,
        },
      );

      if (response.statusCode == 206 || response.statusCode == 200) {
        // 206 = Partial Content (range request succeeded)
        // 200 = OK (server doesn't support range, but returned full file)
        final bytes = response.bodyBytes;
        debugPrint(
            '[PartialVideo] Downloaded ${bytes.length} bytes (requested $maxBytes)');
        return bytes;
      } else {
        debugPrint('[PartialVideo] Failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[PartialVideo] Error: $e');
      return null;
    }
  }

  /// Loads video thumbnail - tries Matrix thumbnail first, then generates from partial video
  Future<Uint8List?> loadVideoThumbnail(Event event) async {
    final cacheKey = '${event.eventId}_video_thumb';

    // Return cached thumbnail immediately
    if (_imageCache.containsKey(cacheKey)) {
      debugPrint(
          '[VideoThumb] Returning cached thumbnail for ${event.eventId}');
      return _imageCache[cacheKey];
    }

    // Return ongoing loading future to prevent duplicate processing
    if (_imageLoading.containsKey(cacheKey)) {
      debugPrint(
          '[VideoThumb] Already loading thumbnail for ${event.eventId}, reusing future');
      return _imageLoading[cacheKey];
    }

    final future = () async {
      try {
        debugPrint('[VideoThumb] Loading thumbnail for video ${event.eventId}');

        // ── Layer 0: Direct HTTP fetch from info.thumbnail_url (fastest, no canvas) ──
        // Matrix events from most clients embed a pre-generated thumbnail image URL
        // directly inside info. We can fetch this tiny image with a single HTTP GET.
        final info = event.content['info'];
        if (info is Map) {
          final thumbMxcUrl = info['thumbnail_url'] as String?;
          if (thumbMxcUrl != null && thumbMxcUrl.startsWith('mxc://')) {
            try {
              final mediaRequest =
                  matrixProvider.service.getMediaRequest(thumbMxcUrl);
              if (mediaRequest != null) {
                final response = await http.get(
                  mediaRequest.uri,
                  headers: mediaRequest.headers,
                );
                if (response.statusCode == 200 &&
                    response.bodyBytes.isNotEmpty) {
                  debugPrint(
                      '[VideoThumb] Layer 0: Got thumbnail via info.thumbnail_url (${response.bodyBytes.length} bytes)');
                  _cacheThumbnail(cacheKey, response.bodyBytes);
                  _imageLoading.remove(cacheKey);
                  return response.bodyBytes;
                }
              }
            } catch (e) {
              debugPrint('[VideoThumb] Layer 0 failed: $e');
            }
          }
        }

        // ── Layer 1: Matrix SDK thumbnail (handles encrypted rooms) ──
        if (event.hasThumbnail) {
          try {
            final matrixFile = await event.downloadAndDecryptAttachment(
              getThumbnail: true,
              downloadCallback: authenticatedDownload(),
            );
            final bytes = matrixFile.bytes;
            if (bytes.isNotEmpty) {
              debugPrint(
                  '[VideoThumb] Layer 1: Got SDK thumbnail: ${bytes.length} bytes');
              _cacheThumbnail(cacheKey, bytes);
              _imageLoading.remove(cacheKey);
              return bytes;
            }
          } catch (e) {
            debugPrint('[VideoThumb] Layer 1 failed: $e');
          }
        }

        // Try to download first 2 MB of video for thumbnail generation
        debugPrint(
            '[VideoThumb] No Matrix thumbnail, downloading partial video...');
        final partialVideoBytes =
            await downloadPartialVideo(event, maxBytes: 2097152); // 2 MB

        if (partialVideoBytes != null && partialVideoBytes.isNotEmpty) {
          debugPrint(
              '[VideoThumb] Got partial video: ${partialVideoBytes.length} bytes, generating thumbnail...');

          // Get mime type from event
          final info = event.content['info'];
          final mimeType =
              (info is Map ? info['mimetype'] as String? : null) ?? 'video/mp4';

          // Generate thumbnail from partial video
          final generatedThumb = await _generateVideoThumbnail(
            partialVideoBytes,
            mimeType,
          );

          if (generatedThumb != null && generatedThumb.isNotEmpty) {
            debugPrint(
                '[VideoThumb] Generated thumbnail from partial video: ${generatedThumb.length} bytes');
            _cacheThumbnail(cacheKey, generatedThumb);
            _imageLoading.remove(cacheKey);
            return generatedThumb;
          } else {
            debugPrint(
                '[VideoThumb] Partial video thumbnail generation failed, trying full video...');
          }
        }

        // Fallback: If partial download failed, download full video
        debugPrint('[VideoThumb] Fallback to full video download...');
        final matrixFile = await event.downloadAndDecryptAttachment(
          getThumbnail: false,
          downloadCallback: authenticatedDownload(),
        );
        final videoBytes = matrixFile.bytes;

        if (videoBytes.isNotEmpty) {
          debugPrint(
              '[VideoThumb] Downloaded full video: ${videoBytes.length} bytes, generating thumbnail...');

          final generatedThumb = await _generateVideoThumbnail(
            videoBytes,
            matrixFile.mimeType,
          );

          if (generatedThumb != null && generatedThumb.isNotEmpty) {
            debugPrint(
                '[VideoThumb] Generated thumbnail: ${generatedThumb.length} bytes');
            _cacheThumbnail(cacheKey, generatedThumb);
            _imageLoading.remove(cacheKey);
            return generatedThumb;
          } else {
            debugPrint(
                '[VideoThumb] Thumbnail generation returned null or empty');
          }
        }
      } catch (e) {
        debugPrint('[VideoThumb] Error loading video thumbnail: $e');
      } finally {
        _imageLoading.remove(cacheKey);
      }
      return null;
    }();

    _imageLoading[cacheKey] = future;
    return future;
  }

  /// Platform-aware video thumbnail generation.
  /// On web: uses canvas-based frame grab via web_video.
  /// On native (Android/iOS): writes bytes to a temp file and uses video_thumbnail plugin.
  Future<Uint8List?> _generateVideoThumbnail(
    Uint8List videoBytes,
    String mimeType,
  ) async {
    if (videoBytes.isEmpty) return null;

    // 1. Try web implementation first (returns null on native platforms via stub)
    final webThumb =
        await web_video.generateVideoThumbnail(videoBytes, mimeType);
    if (webThumb != null && webThumb.isNotEmpty) {
      return webThumb;
    }

    // 2. Native fallback — video_thumbnail requires a file path, not raw bytes.
    //    We write a temp file, extract the frame, then immediately delete it.
    if (kIsWeb) return null; // web already tried above
    return _generateNativeThumbnail(videoBytes);
  }

  Future<Uint8List?> _generateNativeThumbnail(Uint8List videoBytes) async {
    try {
      return await generateNativeThumbnail(videoBytes);
    } catch (e) {
      debugPrint('[VideoThumb] Native fallback generation failed: $e');
      return null;
    }
  }

  /// Pick and send file
  Future<void> pickAndSendFile(
      String roomId, Function(bool) setUploading) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final fileName = picked.name;

    setUploading(true);

    try {
      final matrixFile = MatrixFile(
        bytes: bytes,
        name: fileName,
        mimeType: 'application/octet-stream',
      );
      await matrixProvider.service.sendFile(roomId, matrixFile);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setUploading(false);
    }
  }

  /// Pick and send an audio file.
  Future<void> pickAndSendAudio(
    String roomId,
    Function(bool) setUploading,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final fileName = picked.name;
    final mimeType = lookupMimeType(fileName) ?? 'audio/mpeg';

    setUploading(true);

    try {
      final matrixFile = MatrixAudioFile(
        bytes: bytes,
        name: fileName,
        mimeType: mimeType,
      );
      await matrixProvider.service.sendFile(roomId, matrixFile);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setUploading(false);
    }
  }

  /// Capture a photo with the native camera and send it as an image.
  Future<void> captureAndSendPhoto(
    String roomId,
    Function(bool) setUploading,
    CameraDevice cameraDevice,
  ) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: cameraDevice,
          maxWidth: 1440,
          maxHeight: 1920,
          imageQuality: 82,
        ) ??
        await _retrieveLostPickedImage(picker);
    if (photo == null) return;

    await sendPickedPhoto(roomId, setUploading, photo);
  }

  Future<bool> recoverLostPhoto(
    String roomId,
    Function(bool) setUploading,
  ) async {
    final photo = await _retrieveLostPickedImage(ImagePicker());
    if (photo == null) return false;
    await sendPickedPhoto(roomId, setUploading, photo);
    return true;
  }

  Future<void> sendPickedPhoto(
    String roomId,
    Function(bool) setUploading,
    XFile photo,
  ) async {
    final bytes = await photo.readAsBytes();
    if (bytes.isEmpty) return;

    final fileName = photo.name.isNotEmpty
        ? photo.name
        : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final mimeType = lookupMimeType(fileName, headerBytes: bytes) ??
        photo.mimeType ??
        'image/jpeg';

    await sendPhotoBytes(
      roomId,
      setUploading,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  Future<void> sendPhotoBytes(
    String roomId,
    Function(bool) setUploading, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String caption = '',
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
    bool rethrowErrors = false,
  }) async {
    if (bytes.isEmpty) return;

    setUploading(true);

    try {
      await matrixProvider.service.sendImageWithCaption(
        roomId: roomId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        caption: caption,
        onUploadProgress: onUploadProgress,
        isCancelled: isCancelled,
      );
    } catch (e) {
      if (e is MatrixUploadCancelledException) rethrow;
      if (rethrowErrors) rethrow;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setUploading(false);
    }
  }

  Future<void> sendVideoBytes(
    String roomId,
    Function(bool) setUploading, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String caption = '',
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
    bool rethrowErrors = false,
  }) async {
    if (bytes.isEmpty) return;

    setUploading(true);

    try {
      final videoMetadata = await _readVideoMetadata(bytes);
      Uint8List? thumbBytes;
      ({int width, int height})? thumbDimensions;
      try {
        debugPrint('[Send] Generating camera video thumbnail before upload...');
        thumbBytes = await _generateVideoThumbnail(bytes, mimeType);
        if (thumbBytes != null && thumbBytes.isNotEmpty) {
          thumbDimensions = await _decodeImageDimensions(thumbBytes);
        }
      } catch (e) {
        debugPrint('[Send] Camera video thumbnail failed (non-fatal): $e');
      }

      await matrixProvider.service.sendVideoWithThumbnail(
        roomId: roomId,
        videoBytes: bytes,
        videoFileName: fileName,
        videoMimeType: mimeType,
        thumbBytes: thumbBytes,
        videoWidth: videoMetadata?.width,
        videoHeight: videoMetadata?.height,
        durationMs: videoMetadata?.durationMs,
        thumbnailWidth: thumbDimensions?.width,
        thumbnailHeight: thumbDimensions?.height,
        caption: caption,
        onUploadProgress: onUploadProgress,
        isCancelled: isCancelled,
      );
    } catch (e) {
      if (e is MatrixUploadCancelledException) rethrow;
      if (rethrowErrors) rethrow;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setUploading(false);
    }
  }

  Future<Uint8List?> createVideoPreviewThumbnail(
    Uint8List bytes,
    String mimeType,
  ) {
    return _generateVideoThumbnail(bytes, mimeType);
  }

  Future<({int? width, int? height, int? durationMs})?>
      readVideoPreviewMetadata(Uint8List bytes) async {
    final metadata = await _readVideoMetadata(bytes);
    if (metadata == null) return null;
    return (
      width: metadata.width,
      height: metadata.height,
      durationMs: metadata.durationMs,
    );
  }

  Future<XFile?> _retrieveLostPickedImage(ImagePicker picker) async {
    try {
      final response = await picker.retrieveLostData();
      if (response.isEmpty ||
          response.files == null ||
          response.files!.isEmpty) {
        return null;
      }
      return response.files!.first;
    } catch (e) {
      debugPrint('[Camera] Failed to retrieve lost image picker data: $e');
      return null;
    }
  }

  Future<({int width, int height})?> _decodeImageDimensions(
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final dimensions = (width: image.width, height: image.height);
      image.dispose();
      return dimensions;
    } catch (e) {
      debugPrint('[Media] Failed to decode image dimensions: $e');
      return null;
    }
  }

  Future<NativeVideoMetadata?> _readVideoMetadata(Uint8List bytes) async {
    if (bytes.isEmpty || kIsWeb) return null;
    return readNativeVideoMetadata(bytes);
  }

  /// Pick and send image
  Future<void> pickAndSendImage(
      String roomId, Function(bool) setUploading) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final fileName = picked.name;
    final mimeType = lookupMimeType(fileName) ?? 'image/png';

    setUploading(true);

    try {
      final matrixFile = MatrixImageFile(
        bytes: bytes,
        name: fileName,
        mimeType: mimeType,
      );
      await matrixProvider.service.sendFile(roomId, matrixFile);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setUploading(false);
    }
  }

  /// Pick and send from gallery (images/videos only)
  Future<void> pickAndSendGallery(
      String roomId, Function(bool) setUploading) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        // Image formats
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'heic', 'heif',
        // Video formats
        'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv', 'm4v', '3gp',
      ],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final fileName = picked.name;
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';

    // Double-check that it's actually an image or video
    if (!mimeType.startsWith('image/') && !mimeType.startsWith('video/')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select only photos or videos'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setUploading(true);

    try {
      if (mimeType.startsWith('video/')) {
        final videoMetadata = await _readVideoMetadata(bytes);
        // Generate thumbnail at send time — embedded in the event so
        // every receiver loads it instantly (one HTTP GET, no canvas).
        Uint8List? thumbBytes;
        ({int width, int height})? thumbDimensions;
        try {
          debugPrint('[Send] Generating video thumbnail before upload...');
          thumbBytes = await _generateVideoThumbnail(bytes, mimeType);
          if (thumbBytes != null && thumbBytes.isNotEmpty) {
            thumbDimensions = await _decodeImageDimensions(thumbBytes);
          }
          debugPrint('[Send] Thumbnail: ${thumbBytes?.length ?? 0} bytes');
        } catch (e) {
          debugPrint('[Send] Thumbnail generation failed (non-fatal): $e');
        }

        await matrixProvider.service.sendVideoWithThumbnail(
          roomId: roomId,
          videoBytes: bytes,
          videoFileName: fileName,
          videoMimeType: mimeType,
          thumbBytes: thumbBytes,
          videoWidth: videoMetadata?.width,
          videoHeight: videoMetadata?.height,
          durationMs: videoMetadata?.durationMs,
          thumbnailWidth: thumbDimensions?.width,
          thumbnailHeight: thumbDimensions?.height,
        );
      } else {
        final matrixFile = MatrixImageFile(
          bytes: bytes,
          name: fileName,
          mimeType: mimeType,
        );
        await matrixProvider.service.sendFile(roomId, matrixFile);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send media: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setUploading(false);
    }
  }

  /// Clear cache
  void clearCache() {
    _imageCache.clear();
    _imageLoading.clear();
  }
}
