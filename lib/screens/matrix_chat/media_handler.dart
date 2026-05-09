import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:matrix/matrix.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import '../../providers/matrix_provider.dart';
import '../web_video_view_stub.dart' if (dart.library.html) '../web_video_view.dart' as web_video;

/// Handles all media-related operations (upload, download, caching)
class MediaHandler {
  final MatrixProvider matrixProvider;
  final BuildContext context;
  
  // Global in-memory image cache (persists across chat screen navigations)
  static final Map<String, Uint8List> _imageCache = {};
  static final Map<String, Future<Uint8List?>> _imageLoading = {};

  /// Gets the persistent Hive cache box (opened in MatrixService.init)
  static Box<Uint8List>? get _hiveCache {
    return Hive.isBoxOpen('xmo_media_cache') ? Hive.box<Uint8List>('xmo_media_cache') : null;
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
    final token = matrixProvider.service.accessToken;
    return (Uri url) async {
      var newUrl = url;
      final path = url.path;
      if (path.contains('/_matrix/media/')) {
        final newPath = path.replaceFirst('/_matrix/media/v3/', '/_matrix/client/v1/media/');
        final queryParams = Map<String, String>.from(url.queryParameters);
        if (token != null) queryParams['access_token'] = token;
        newUrl = url.replace(path: newPath, queryParameters: queryParams);
      } else if (token != null) {
        final queryParams = Map<String, String>.from(url.queryParameters);
        queryParams['access_token'] = token;
        newUrl = url.replace(queryParameters: queryParams);
      }
      debugPrint('[MediaDownload] Fetching: $newUrl');
      final response = await http.get(newUrl);
      if (response.statusCode != 200) {
        throw Exception('Media download failed: ${response.statusCode} ${response.reasonPhrase}');
      }
      return response.bodyBytes;
    };
  }

  /// Downloads image bytes from event with caching
  Future<Uint8List?> loadImageBytes(Event event, {bool getThumbnail = false}) async {
    final cacheKey = '${event.eventId}_$getThumbnail';
    if (_imageCache.containsKey(cacheKey)) return _imageCache[cacheKey];
    if (_imageLoading.containsKey(cacheKey)) return _imageLoading[cacheKey];

    final future = () async {
      try {
        debugPrint('[ImageLoad] Loading ${getThumbnail ? "thumbnail" : "full"} for event ${event.eventId}');
        debugPrint('[ImageLoad] Event type: ${event.type}, messageType: ${event.messageType}');
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
  Future<Uint8List?> downloadPartialVideo(Event event, {int maxBytes = 2097152}) async {
    try {
      final mxcUrl = event.content['url'] as String?;
      if (mxcUrl == null || !mxcUrl.startsWith('mxc://')) {
        debugPrint('[PartialVideo] Invalid MXC URL');
        return null;
      }

      // Parse MXC URL: mxc://server/mediaId
      final uri = Uri.parse(mxcUrl);
      final serverName = uri.host;
      final mediaId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';

      if (serverName.isEmpty || mediaId.isEmpty) {
        debugPrint('[PartialVideo] Invalid MXC URL format');
        return null;
      }

      // Build download URL
      final token = matrixProvider.service.accessToken;
      final baseUrl = matrixProvider.service.client.homeserver?.toString() ?? '';
      final downloadPath = '/_matrix/client/v1/media/download/$serverName/$mediaId';
      
      var downloadUrl = Uri.parse('$baseUrl$downloadPath');
      if (token != null) {
        downloadUrl = downloadUrl.replace(
          queryParameters: {'access_token': token},
        );
      }

      debugPrint('[PartialVideo] Requesting first $maxBytes bytes from: $downloadUrl');

      // Make HTTP request with Range header to get only first chunk
      final response = await http.get(
        downloadUrl,
        headers: {
          'Range': 'bytes=0-${maxBytes - 1}', // Request first 2 MB
        },
      );

      if (response.statusCode == 206 || response.statusCode == 200) {
        // 206 = Partial Content (range request succeeded)
        // 200 = OK (server doesn't support range, but returned full file)
        final bytes = response.bodyBytes;
        debugPrint('[PartialVideo] Downloaded ${bytes.length} bytes (requested $maxBytes)');
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
      debugPrint('[VideoThumb] Returning cached thumbnail for ${event.eventId}');
      return _imageCache[cacheKey];
    }
    
    // Return ongoing loading future to prevent duplicate processing
    if (_imageLoading.containsKey(cacheKey)) {
      debugPrint('[VideoThumb] Already loading thumbnail for ${event.eventId}, reusing future');
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
              final httpUrl = matrixProvider.service.getHttpUrl(thumbMxcUrl);
              if (httpUrl != null) {
                final response = await http.get(httpUrl);
                if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
                  debugPrint('[VideoThumb] Layer 0: Got thumbnail via info.thumbnail_url (${response.bodyBytes.length} bytes)');
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
              debugPrint('[VideoThumb] Layer 1: Got SDK thumbnail: ${bytes.length} bytes');
              _cacheThumbnail(cacheKey, bytes);
              _imageLoading.remove(cacheKey);
              return bytes;
            }
          } catch (e) {
            debugPrint('[VideoThumb] Layer 1 failed: $e');
          }
        }

        // Try to download first 2 MB of video for thumbnail generation
        debugPrint('[VideoThumb] No Matrix thumbnail, downloading partial video...');
        final partialVideoBytes = await downloadPartialVideo(event, maxBytes: 2097152); // 2 MB
        
        if (partialVideoBytes != null && partialVideoBytes.isNotEmpty) {
          debugPrint('[VideoThumb] Got partial video: ${partialVideoBytes.length} bytes, generating thumbnail...');
          
          // Get mime type from event
          final info = event.content['info'];
          final mimeType = (info is Map ? info['mimetype'] as String? : null) ?? 'video/mp4';
          
          // Generate thumbnail from partial video
          final generatedThumb = await web_video.generateVideoThumbnail(
            partialVideoBytes,
            mimeType,
          );
          
          if (generatedThumb != null && generatedThumb.isNotEmpty) {
            debugPrint('[VideoThumb] Generated thumbnail from partial video: ${generatedThumb.length} bytes');
            _cacheThumbnail(cacheKey, generatedThumb);
            _imageLoading.remove(cacheKey);
            return generatedThumb;
          } else {
            debugPrint('[VideoThumb] Partial video thumbnail generation failed, trying full video...');
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
          debugPrint('[VideoThumb] Downloaded full video: ${videoBytes.length} bytes, generating thumbnail...');
          
          final generatedThumb = await web_video.generateVideoThumbnail(
            videoBytes,
            matrixFile.mimeType,
          );
          
          if (generatedThumb != null && generatedThumb.isNotEmpty) {
            debugPrint('[VideoThumb] Generated thumbnail: ${generatedThumb.length} bytes');
            _cacheThumbnail(cacheKey, generatedThumb);
            _imageLoading.remove(cacheKey);
            return generatedThumb;
          } else {
            debugPrint('[VideoThumb] Thumbnail generation returned null or empty');
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

  /// Pick and send file
  Future<void> pickAndSendFile(String roomId, Function(bool) setUploading) async {
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

  /// Pick and send image
  Future<void> pickAndSendImage(String roomId, Function(bool) setUploading) async {
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
  Future<void> pickAndSendGallery(String roomId, Function(bool) setUploading) async {
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
        // Generate thumbnail at send time — embedded in the event so
        // every receiver loads it instantly (one HTTP GET, no canvas).
        Uint8List? thumbBytes;
        try {
          debugPrint('[Send] Generating video thumbnail before upload...');
          thumbBytes = await web_video.generateVideoThumbnail(bytes, mimeType);
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
