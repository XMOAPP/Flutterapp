import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import '../models/xmo_stream_manifest.dart';
import 'matrix_encrypted_media_helper.dart';
import 'matrix_media_helper.dart';

typedef XmoStreamChunkDownloader =
    Future<Uint8List> Function(
      MatrixMediaRequest request,
      XmoStreamChunk chunk,
    );

typedef XmoStreamCacheDirectoryProvider = Future<Directory> Function();

enum XmoStreamingMediaPhase {
  preparing,
  ready,
  prefetching,
  complete,
  failed,
  cancelled,
  cleanedUp,
}

class XmoStreamingMediaState {
  const XmoStreamingMediaState({
    required this.eventId,
    required this.phase,
    required this.cachedBytes,
    required this.totalBytes,
    this.chunkIndex,
    this.error,
  });

  final String eventId;
  final XmoStreamingMediaPhase phase;
  final int cachedBytes;
  final int totalBytes;
  final int? chunkIndex;
  final Object? error;

  bool get isReady => phase == XmoStreamingMediaPhase.ready;
  bool get isTerminal =>
      phase == XmoStreamingMediaPhase.complete ||
      phase == XmoStreamingMediaPhase.failed ||
      phase == XmoStreamingMediaPhase.cancelled ||
      phase == XmoStreamingMediaPhase.cleanedUp;
}

class XmoStreamingMediaException implements Exception {
  const XmoStreamingMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StreamingMediaService {
  StreamingMediaService({
    required MatrixMediaHelper mediaHelper,
    MatrixEncryptedMediaHelper encryptedMediaHelper =
        const MatrixEncryptedMediaHelper(),
    XmoStreamChunkDownloader? downloader,
    XmoStreamCacheDirectoryProvider? cacheDirectoryProvider,
    int maxRetries = 3,
    int maxCacheBytes = 256 * 1024 * 1024,
  }) : assert(maxRetries > 0),
       assert(maxCacheBytes > 0),
       _mediaHelper = mediaHelper,
       _encryptedMediaHelper = encryptedMediaHelper,
       _downloader = downloader,
       _cacheDirectoryProvider = cacheDirectoryProvider,
       _maxRetries = maxRetries,
       _maxCacheBytes = maxCacheBytes;

  final MatrixMediaHelper _mediaHelper;
  final MatrixEncryptedMediaHelper _encryptedMediaHelper;
  final XmoStreamChunkDownloader? _downloader;
  final XmoStreamCacheDirectoryProvider? _cacheDirectoryProvider;
  final int _maxRetries;
  final int _maxCacheBytes;
  final Map<String, Future<XmoStreamingMediaSession>> _activeSessions =
      <String, Future<XmoStreamingMediaSession>>{};

  Future<XmoStreamingMediaSession> openFromEventContent({
    required String eventId,
    required Map<dynamic, dynamic> content,
    String quality = 'source',
  }) async {
    final manifest = XmoStreamManifest.fromEventContent(content);
    if (manifest == null) {
      throw const XmoStreamingMediaException(
        'This event does not contain xmo_stream media.',
      );
    }
    return open(eventId: eventId, manifest: manifest, quality: quality);
  }

  Future<XmoStreamingMediaSession> open({
    required String eventId,
    required XmoStreamManifest manifest,
    String quality = 'source',
  }) async {
    final cacheKey = '$eventId::$quality';
    final existing = _activeSessions[cacheKey];
    if (existing != null) {
      final session = await existing;
      if (!session.isClosed) return session;
      _activeSessions.remove(cacheKey);
    }

    final pending = _openNewSession(
      eventId: eventId,
      manifest: manifest,
      quality: quality,
    );
    _activeSessions[cacheKey] = pending;
    try {
      final session = await pending;
      session.closed.whenComplete(() {
        final current = _activeSessions[cacheKey];
        if (identical(current, pending)) {
          _activeSessions.remove(cacheKey);
        }
      });
      return session;
    } catch (_) {
      final current = _activeSessions[cacheKey];
      if (identical(current, pending)) {
        _activeSessions.remove(cacheKey);
      }
      rethrow;
    }
  }

  Future<XmoStreamingMediaSession> _openNewSession({
    required String eventId,
    required XmoStreamManifest manifest,
    required String quality,
  }) async {
    final selectedQuality = manifest.quality(quality) ?? manifest.sourceQuality;
    if (selectedQuality == null) {
      throw XmoStreamingMediaException(
        'xmo_stream quality "$quality" is not available.',
      );
    }

    final root = await (_cacheDirectoryProvider ?? _defaultCacheDirectory)();
    final cacheDirectory = Directory(
      '${root.path}${Platform.pathSeparator}${_safePathSegment(eventId)}',
    );
    await cacheDirectory.create(recursive: true);

    final session = XmoStreamingMediaSession._(
      eventId: eventId,
      manifest: manifest,
      qualityName: quality,
      quality: selectedQuality,
      cacheDirectory: cacheDirectory,
      mediaHelper: _mediaHelper,
      encryptedMediaHelper: _encryptedMediaHelper,
      downloader: _downloader ?? _defaultDownloader,
      maxRetries: _maxRetries,
      maxCacheBytes: _maxCacheBytes,
    );
    await session.prepare();
    return session;
  }

  Future<void> cleanupCache({
    Duration maxAge = const Duration(hours: 12),
    int? maxTotalBytes,
  }) async {
    final root = await (_cacheDirectoryProvider ?? _defaultCacheDirectory)();
    await cleanupCacheDirectory(
      root,
      maxAge: maxAge,
      maxTotalBytes: maxTotalBytes ?? _maxCacheBytes,
    );
  }

  static Future<void> cleanupDefaultCache({
    Duration maxAge = const Duration(hours: 12),
    int maxTotalBytes = 256 * 1024 * 1024,
  }) async {
    final root = await _defaultCacheDirectory();
    await cleanupCacheDirectory(
      root,
      maxAge: maxAge,
      maxTotalBytes: maxTotalBytes,
    );
  }

  static Future<void> cleanupCacheDirectory(
    Directory root, {
    required Duration maxAge,
    required int maxTotalBytes,
    DateTime? now,
  }) async {
    if (!await root.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    final entries = <_CacheEntry>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final entry = await _cacheEntryFor(entity);
      if (entry == null) continue;
      if (entry.modified.isBefore(cutoff)) {
        await _deleteDirectoryIfExists(entity);
      } else {
        entries.add(entry);
      }
    }

    var totalBytes = entries.fold<int>(
      0,
      (total, entry) => total + entry.bytes,
    );
    if (totalBytes <= maxTotalBytes) return;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (totalBytes <= maxTotalBytes) break;
      await _deleteDirectoryIfExists(entry.directory);
      totalBytes -= entry.bytes;
    }
  }

  static Future<Directory> _defaultCacheDirectory() async {
    final root = await getTemporaryDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}xmo_streaming_media',
    );
  }

  static Future<Uint8List> _defaultDownloader(
    MatrixMediaRequest request,
    XmoStreamChunk chunk,
  ) async {
    final client = HttpClient();
    try {
      final httpRequest = await client.getUrl(request.uri);
      httpRequest.followRedirects = false;
      request.headers.forEach(httpRequest.headers.set);
      var response = await httpRequest.close();
      if (_isRedirect(response.statusCode)) {
        final location = response.redirects.isNotEmpty
            ? response.redirects.last.location
            : _redirectLocation(response, request.uri);
        await response.drain<void>();
        if (location == null || location.scheme != 'https') {
          throw XmoStreamingMediaException(
            'Stream chunk ${chunk.index} returned an unsafe redirect.',
          );
        }
        final redirectedRequest = await client.getUrl(location);
        redirectedRequest.followRedirects = false;
        response = await redirectedRequest.close();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw XmoStreamingMediaException(
          'Failed to download stream chunk ${chunk.index} '
          '(${response.statusCode}).',
        );
      }
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } finally {
      client.close(force: true);
    }
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  static Uri? _redirectLocation(HttpClientResponse response, Uri base) {
    final value = response.headers.value(HttpHeaders.locationHeader);
    if (value == null || value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    return parsed == null ? null : base.resolveUri(parsed);
  }
}

class XmoStreamingMediaSession {
  XmoStreamingMediaSession._({
    required this.eventId,
    required this.manifest,
    required this.qualityName,
    required this.quality,
    required this.cacheDirectory,
    required MatrixMediaHelper mediaHelper,
    required MatrixEncryptedMediaHelper encryptedMediaHelper,
    required XmoStreamChunkDownloader downloader,
    required int maxRetries,
    required int maxCacheBytes,
  }) : _mediaHelper = mediaHelper,
       _encryptedMediaHelper = encryptedMediaHelper,
       _downloader = downloader,
       _maxRetries = maxRetries,
       _maxCacheBytes = maxCacheBytes;

  final String eventId;
  final XmoStreamManifest manifest;
  final String qualityName;
  final XmoStreamQuality quality;
  final Directory cacheDirectory;

  final MatrixMediaHelper _mediaHelper;
  final MatrixEncryptedMediaHelper _encryptedMediaHelper;
  final XmoStreamChunkDownloader _downloader;
  final int _maxRetries;
  final int _maxCacheBytes;
  final StreamController<XmoStreamingMediaState> _states =
      StreamController<XmoStreamingMediaState>.broadcast();
  final Map<int, Future<File>> _inFlightChunks = <int, Future<File>>{};
  final Set<int> _cachedChunkIndexes = <int>{};

  bool _cancelled = false;
  bool _cleanedUp = false;
  int _cachedBytes = 0;
  final Completer<void> _closed = Completer<void>();

  Stream<XmoStreamingMediaState> get states => _states.stream;

  List<XmoStreamChunk> get chunks => quality.chunks;

  int get totalBytes => quality.size ?? manifest.size;

  int get chunkSize => quality.chunkSize ?? manifest.chunkSize;

  String get mimeType => quality.mimeType ?? manifest.mimeType;

  bool get isCancelled => _cancelled;

  bool get isClosed => _cancelled || _cleanedUp;

  Future<void> get closed => _closed.future;

  int get cachedBytes => _cachedBytes;

  Future<void> prepare() async {
    _emit(XmoStreamingMediaPhase.preparing, chunkIndex: 0);
    try {
      await ensureChunk(0);
      _emit(XmoStreamingMediaPhase.ready, chunkIndex: 0);
      unawaited(_prefetchRemainingChunks());
    } catch (e) {
      if (_cancelled) {
        _emit(XmoStreamingMediaPhase.cancelled, error: e);
      } else {
        _emit(XmoStreamingMediaPhase.failed, chunkIndex: 0, error: e);
      }
      rethrow;
    }
  }

  Future<File> ensureChunk(int index) {
    _throwIfUnavailable();
    if (index < 0 || index >= chunks.length) {
      throw RangeError.index(index, chunks, 'index');
    }

    final cached = chunkFile(index);
    if (cached.existsSync()) {
      _cachedChunkIndexes.add(index);
      return Future<File>.value(cached);
    }

    return _inFlightChunks.putIfAbsent(index, () async {
      try {
        return await _downloadDecryptAndCache(chunks[index]);
      } finally {
        _inFlightChunks.remove(index);
      }
    });
  }

  File chunkFile(int index) {
    return File(
      '${cacheDirectory.path}${Platform.pathSeparator}chunk_$index.bin',
    );
  }

  Future<void> retryFailedChunk(int index) async {
    _throwIfUnavailable();
    await _deleteFileIfExists(chunkFile(index));
    _cachedChunkIndexes.remove(index);
    await ensureChunk(index);
  }

  void cancel() {
    if (_cancelled || _cleanedUp) return;
    _cancelled = true;
    if (!_closed.isCompleted) _closed.complete();
    _emit(XmoStreamingMediaPhase.cancelled);
  }

  Future<void> cleanup() async {
    if (_cleanedUp) return;
    _cleanedUp = true;
    _cancelled = true;
    await _deleteDirectoryIfExists(cacheDirectory);
    _cachedChunkIndexes.clear();
    _cachedBytes = 0;
    if (!_closed.isCompleted) _closed.complete();
    _emit(XmoStreamingMediaPhase.cleanedUp);
    await _states.close();
  }

  Future<void> _prefetchRemainingChunks() async {
    for (var i = 1; i < chunks.length; i++) {
      if (_cancelled || _cleanedUp) return;
      _emit(XmoStreamingMediaPhase.prefetching, chunkIndex: i);
      try {
        await ensureChunk(i);
      } catch (e) {
        if (_cancelled || _cleanedUp) return;
        _emit(XmoStreamingMediaPhase.failed, chunkIndex: i, error: e);
        return;
      }
    }
    if (!_cancelled && !_cleanedUp) {
      _emit(XmoStreamingMediaPhase.complete);
    }
  }

  Future<File> _downloadDecryptAndCache(XmoStreamChunk chunk) async {
    _throwIfUnavailable();
    final request = _requestForChunk(chunk);
    Object? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        _throwIfUnavailable();
        final encryptedBytes = await _downloader(request, chunk);
        _throwIfUnavailable();
        final decryptedBytes = await _decryptChunk(chunk, encryptedBytes);
        _throwIfUnavailable();
        final file = chunkFile(chunk.index);
        await file.writeAsBytes(decryptedBytes, flush: true);
        _cachedChunkIndexes.add(chunk.index);
        _cachedBytes = await _calculateCacheBytes();
        await _enforceCacheLimit(protectedIndex: chunk.index);
        return file;
      } catch (e) {
        await _deleteFileIfExists(chunkFile(chunk.index));
        lastError = e;
        if (_cancelled || _cleanedUp) rethrow;
        if (attempt < _maxRetries - 1) {
          await Future<void>.delayed(_retryDelay(attempt));
        }
      }
    }
    throw XmoStreamingMediaException(
      'Failed to prepare stream chunk ${chunk.index}: $lastError',
    );
  }

  Future<Uint8List> _decryptChunk(
    XmoStreamChunk chunk,
    Uint8List encryptedBytes,
  ) async {
    final decrypted = await _encryptedMediaHelper.decrypt(
      EncryptedFile(
        data: encryptedBytes,
        k: chunk.key,
        iv: chunk.iv,
        sha256: chunk.sha256,
      ),
    );
    if (decrypted == null) {
      throw XmoStreamingMediaException(
        'Stream chunk ${chunk.index} failed hash verification.',
      );
    }
    return decrypted;
  }

  MatrixMediaRequest _requestForChunk(XmoStreamChunk chunk) {
    final uri = Uri.parse(chunk.url);
    if (uri.isScheme('mxc')) {
      final request = _mediaHelper.fromMxc(chunk.url);
      if (request == null) {
        throw XmoStreamingMediaException(
          'Invalid stream chunk URL: ${chunk.url}',
        );
      }
      return request;
    }
    return _mediaHelper.fromUrl(uri);
  }

  Future<void> _enforceCacheLimit({required int protectedIndex}) async {
    _cachedBytes = await _calculateCacheBytes();
    if (_cachedBytes <= _maxCacheBytes) return;

    final indexes = _cachedChunkIndexes.toList()..sort();
    for (final index in indexes) {
      if (_cachedBytes <= _maxCacheBytes) break;
      if (index == protectedIndex) continue;
      final file = chunkFile(index);
      if (await file.exists()) {
        final length = await file.length();
        await _deleteFileIfExists(file);
        _cachedBytes -= length;
      }
      _cachedChunkIndexes.remove(index);
    }
  }

  Future<int> _calculateCacheBytes() async {
    var total = 0;
    if (!await cacheDirectory.exists()) return total;
    await for (final entity in cacheDirectory.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  void _throwIfUnavailable() {
    if (_cleanedUp) {
      throw const XmoStreamingMediaException(
        'Streaming media session has been cleaned up.',
      );
    }
    if (_cancelled) {
      throw const XmoStreamingMediaException(
        'Streaming media session was cancelled.',
      );
    }
  }

  Duration _retryDelay(int attempt) {
    return Duration(milliseconds: 200 * (1 << attempt.clamp(0, 3)));
  }

  void _emit(XmoStreamingMediaPhase phase, {int? chunkIndex, Object? error}) {
    if (_states.isClosed) return;
    _states.add(
      XmoStreamingMediaState(
        eventId: eventId,
        phase: phase,
        cachedBytes: _cachedBytes,
        totalBytes: manifest.size,
        chunkIndex: chunkIndex,
        error: error,
      ),
    );
  }
}

String _safePathSegment(String input) {
  final sanitized = input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  return sanitized.isEmpty ? 'stream' : sanitized;
}

Future<void> _deleteFileIfExists(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Cache files are disposable. A failed delete should not break playback.
  }
}

Future<void> _deleteDirectoryIfExists(Directory directory) async {
  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } catch (_) {
    // Cache directories are disposable. A failed delete should not break UI.
  }
}

Future<_CacheEntry?> _cacheEntryFor(Directory directory) async {
  try {
    var bytes = 0;
    DateTime? modified;
    await for (final entity in directory.list(recursive: true)) {
      final stat = await entity.stat();
      if (entity is File) {
        bytes += stat.size;
        if (modified == null || stat.modified.isAfter(modified)) {
          modified = stat.modified;
        }
      }
    }
    return _CacheEntry(
      directory: directory,
      bytes: bytes,
      modified:
          modified ?? await directory.stat().then((stat) => stat.modified),
    );
  } catch (_) {
    return null;
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.directory,
    required this.bytes,
    required this.modified,
  });

  final Directory directory;
  final int bytes;
  final DateTime modified;
}
