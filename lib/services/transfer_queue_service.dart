import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

enum TransferDirection { upload, download }

enum TransferKind { photo, video, audio, voice, file }

enum TransferStatus { queued, running, paused, completed, failed, cancelled }

class TransferJob {
  final String id;
  final TransferDirection direction;
  final TransferKind kind;
  final String ownerUserId;
  final String roomId;
  final String fileName;
  final String mimeType;
  final String localPath;
  final String? thumbnailPath;
  final int totalBytes;
  final int uploadedBytes;
  final int attempts;
  final int maxAttempts;
  final TransferStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? error;
  final DateTime? nextRetryAt;

  const TransferJob({
    required this.id,
    required this.direction,
    required this.kind,
    required this.ownerUserId,
    required this.roomId,
    required this.fileName,
    required this.mimeType,
    required this.localPath,
    required this.totalBytes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnailPath,
    this.uploadedBytes = 0,
    this.attempts = 0,
    this.maxAttempts = 3,
    this.error,
    this.nextRetryAt,
  });

  double? get progress {
    if (totalBytes <= 0) return null;
    return (uploadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get canRetry =>
      status == TransferStatus.failed || status == TransferStatus.cancelled;

  bool get canCancel =>
      status == TransferStatus.queued ||
      status == TransferStatus.running ||
      status == TransferStatus.paused;

  bool get shouldAutoRetry =>
      status == TransferStatus.failed &&
      attempts < maxAttempts &&
      nextRetryAt != null;

  TransferJob copyWith({
    TransferDirection? direction,
    TransferKind? kind,
    String? ownerUserId,
    String? roomId,
    String? fileName,
    String? mimeType,
    String? localPath,
    String? thumbnailPath,
    int? totalBytes,
    int? uploadedBytes,
    int? attempts,
    int? maxAttempts,
    TransferStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? error,
    DateTime? nextRetryAt,
    bool clearError = false,
    bool clearNextRetryAt = false,
  }) {
    return TransferJob(
      id: id,
      direction: direction ?? this.direction,
      kind: kind ?? this.kind,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      roomId: roomId ?? this.roomId,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      localPath: localPath ?? this.localPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      totalBytes: totalBytes ?? this.totalBytes,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      error: clearError ? null : error ?? this.error,
      nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'direction': direction.name,
      'kind': kind.name,
      'ownerUserId': ownerUserId,
      'roomId': roomId,
      'fileName': fileName,
      'mimeType': mimeType,
      'localPath': localPath,
      'thumbnailPath': thumbnailPath,
      'totalBytes': totalBytes,
      'uploadedBytes': uploadedBytes,
      'attempts': attempts,
      'maxAttempts': maxAttempts,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'error': error,
      'nextRetryAt': nextRetryAt?.toIso8601String(),
    };
  }

  factory TransferJob.fromJson(Map<dynamic, dynamic> json) {
    T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
      if (name is! String) return fallback;
      return values.firstWhere((value) => value.name == name,
          orElse: () => fallback);
    }

    return TransferJob(
      id: json['id'] as String,
      direction: enumByName(
        TransferDirection.values,
        json['direction'],
        TransferDirection.upload,
      ),
      kind: enumByName(TransferKind.values, json['kind'], TransferKind.file),
      ownerUserId: json['ownerUserId'] as String? ?? 'legacy',
      roomId: json['roomId'] as String,
      fileName: json['fileName'] as String,
      mimeType: json['mimeType'] as String,
      localPath: json['localPath'] as String,
      thumbnailPath: json['thumbnailPath'] as String?,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      uploadedBytes: (json['uploadedBytes'] as num?)?.toInt() ?? 0,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 3,
      status: enumByName(
        TransferStatus.values,
        json['status'],
        TransferStatus.queued,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      error: json['error'] as String?,
      nextRetryAt: DateTime.tryParse(json['nextRetryAt'] as String? ?? ''),
    );
  }
}

class TransferQueueService {
  static final TransferQueueService instance = TransferQueueService._();
  TransferQueueService._();

  static const String boxName = 'xmo_transfer_queue';

  Box? _box;
  String? _ownerUserId;
  final Map<String, TransferJob> _jobs = {};
  final Set<String> _cancelledIds = {};
  final _controller = StreamController<List<TransferJob>>.broadcast();

  Stream<List<TransferJob>> get stream => _controller.stream;
  List<TransferJob> get jobs => List.unmodifiable(_jobs.values);

  Future<void> init() async {
    if (_box != null) return;
    _box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await Hive.openBox(boxName);
    _loadPersistedJobs();
  }

  /// Jobs are private to the Matrix account that created them. A device can
  /// legitimately hold several account databases over time, so a global queue
  /// must never resume another user's pending upload.
  Future<void> setCurrentUser(String? userId) async {
    await init();
    final normalized = userId?.trim();
    if (_ownerUserId == normalized) return;
    _ownerUserId = normalized;
    _loadPersistedJobs();
  }

  List<TransferJob> jobsForRoom(String roomId) {
    return _jobs.values
        .where((job) =>
            job.roomId == roomId && job.ownerUserId == _activeOwnerUserId)
        .toList(growable: false);
  }

  String get _activeOwnerUserId => _ownerUserId ?? 'legacy';

  Future<TransferJob> createUploadJob({
    required String roomId,
    required Uint8List bytes,
    Uint8List? thumbnailBytes,
    required String fileName,
    required String mimeType,
    required TransferKind kind,
    String? id,
  }) async {
    await init();
    final now = DateTime.now();
    final jobId = id ?? '${kind.name}_${now.microsecondsSinceEpoch}';
    final baseDir = await _queueDir();
    final payloadPath = '${baseDir.path}${io.Platform.pathSeparator}$jobId.bin';
    await io.File(payloadPath).writeAsBytes(bytes, flush: true);

    String? thumbPath;
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      thumbPath = '${baseDir.path}${io.Platform.pathSeparator}$jobId.thumb';
      await io.File(thumbPath).writeAsBytes(thumbnailBytes, flush: true);
    }

    final job = TransferJob(
      id: jobId,
      direction: TransferDirection.upload,
      kind: kind,
      ownerUserId: _activeOwnerUserId,
      roomId: roomId,
      fileName: fileName,
      mimeType: mimeType,
      localPath: payloadPath,
      thumbnailPath: thumbPath,
      totalBytes: bytes.length,
      status: TransferStatus.queued,
      createdAt: now,
      updatedAt: now,
    );
    await _save(job);
    return job;
  }

  Future<TransferJob> createDownloadJob({
    required String roomId,
    required String fileName,
    required String mimeType,
    required TransferKind kind,
    String? id,
    int totalBytes = 0,
  }) async {
    await init();
    final now = DateTime.now();
    final jobId = id ?? 'download_${kind.name}_${now.microsecondsSinceEpoch}';
    final job = TransferJob(
      id: jobId,
      direction: TransferDirection.download,
      kind: kind,
      ownerUserId: _activeOwnerUserId,
      roomId: roomId,
      fileName: fileName,
      mimeType: mimeType,
      localPath: '',
      totalBytes: totalBytes,
      status: TransferStatus.queued,
      createdAt: now,
      updatedAt: now,
    );
    await _save(job);
    return job;
  }

  Future<Uint8List> readPayload(TransferJob job) {
    return io.File(job.localPath).readAsBytes();
  }

  Future<Uint8List?> readThumbnail(TransferJob job) async {
    final path = job.thumbnailPath;
    if (path == null || path.isEmpty) return null;
    final file = io.File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> markRunning(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    _cancelledIds.remove(id);
    await _save(
      job.copyWith(
        status: TransferStatus.running,
        attempts: job.attempts + 1,
        uploadedBytes: job.uploadedBytes,
        clearError: true,
        clearNextRetryAt: true,
      ),
    );
  }

  Future<void> updateProgress(
    String id,
    int uploadedBytes,
    int totalBytes,
  ) async {
    final job = _jobs[id];
    if (job == null) return;
    final effectiveTotalBytes = totalBytes > 0 ? totalBytes : job.totalBytes;
    await _save(
      job.copyWith(
        uploadedBytes: uploadedBytes,
        totalBytes: effectiveTotalBytes,
        status: TransferStatus.running,
      ),
      persistImmediately: false,
    );
  }

  Future<void> markCompleted(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    await _save(job.copyWith(
      status: TransferStatus.completed,
      uploadedBytes: job.totalBytes,
      clearError: true,
    ));
    await _deletePayloadFiles(job);
  }

  Future<void> markFailed(String id, Object error) async {
    final job = _jobs[id];
    if (job == null) return;
    final nextAttempt = job.attempts;
    final retryAt = nextAttempt < job.maxAttempts
        ? DateTime.now().add(_retryDelay(nextAttempt - 1))
        : null;
    await _save(job.copyWith(
      status: TransferStatus.failed,
      error: _shortError(error),
      nextRetryAt: retryAt,
    ));
  }

  Future<void> cancel(String id) async {
    _cancelledIds.add(id);
    final job = _jobs[id];
    if (job == null) return;
    await _save(job.copyWith(
      status: TransferStatus.cancelled,
      clearNextRetryAt: true,
    ));
  }

  bool isCancelled(String id) => _cancelledIds.contains(id);

  Future<void> retry(String id) async {
    final job = _jobs[id];
    if (job == null || !job.canRetry) return;
    _cancelledIds.remove(id);
    await _save(job.copyWith(
      status: TransferStatus.queued,
      uploadedBytes: 0,
      clearError: true,
      clearNextRetryAt: true,
    ));
  }

  Future<void> remove(String id) async {
    final job = _jobs.remove(id);
    await _box?.delete(_storageKey(id, job?.ownerUserId));
    if (job != null) await _deletePayloadFiles(job);
    _emit();
  }

  Future<void> _save(
    TransferJob job, {
    bool persistImmediately = true,
  }) async {
    _jobs[job.id] = job;
    if (persistImmediately) {
      await _box?.put(_storageKey(job.id, job.ownerUserId), job.toJson());
    }
    _emit();
  }

  void _loadPersistedJobs() {
    _jobs.clear();
    for (final key in _box?.keys ?? const []) {
      final raw = _box?.get(key);
      if (raw is Map) {
        try {
          final job = TransferJob.fromJson(raw);
          if (job.ownerUserId != _activeOwnerUserId) continue;
          if (job.status == TransferStatus.running ||
              job.status == TransferStatus.paused) {
            _jobs[job.id] = job.copyWith(status: TransferStatus.queued);
          } else {
            _jobs[job.id] = job;
          }
        } catch (e) {
          debugPrint('[TransferQueue] Failed to load job $key: $e');
        }
      }
    }
    _emit();
  }

  DateTime? retryAtFor(String id) => _jobs[id]?.nextRetryAt;

  bool shouldAutoRetry(String id) {
    final job = _jobs[id];
    return job?.shouldAutoRetry == true;
  }

  Duration _retryDelay(int attempts) {
    // 2s, 4s, 8s, capped to keep an app restart from creating a long stall.
    final seconds = 2 * (1 << attempts.clamp(0, 2));
    return Duration(seconds: seconds.clamp(2, 8));
  }

  String _storageKey(String id, String? ownerUserId) =>
      '${ownerUserId ?? 'legacy'}::$id';

  Future<io.Directory> _queueDir() async {
    final root = await getTemporaryDirectory();
    final dir = io.Directory(
      '${root.path}${io.Platform.pathSeparator}xmo_transfer_queue',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _deletePayloadFiles(TransferJob job) async {
    for (final path in [job.localPath, job.thumbnailPath]) {
      if (path == null || path.isEmpty) continue;
      try {
        final file = io.File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('[TransferQueue] Failed to delete $path: $e');
      }
    }
  }

  String _shortError(Object error) {
    final text = error.toString();
    return text.length > 180 ? '${text.substring(0, 180)}...' : text;
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(jobs);
    }
  }
}
