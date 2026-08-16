import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/story_models.dart';
import '../utils/user_facing_error.dart';
import 'story_service.dart';

enum StoryUploadStatus { queued, running, completed, failed, cancelled }

class StoryUploadJob {
  final String id;
  final String ownerUserId;
  final StoryMediaType mediaType;
  final String? mediaPath;
  final int mediaSizeBytes;
  final String? mediaMimeType;
  final String? mediaFileName;
  final String? thumbnailPath;
  final String? caption;
  final String? textContent;
  final StoryPrivacy privacy;
  final List<String>? customPrivacyList;
  final StoryUploadStatus status;
  final StoryCreationPhase phase;
  final int uploadedBytes;
  final int totalBytes;
  final int attempts;
  final int maxAttempts;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextRetryAt;
  final String? error;

  const StoryUploadJob({
    required this.id,
    required this.ownerUserId,
    required this.mediaType,
    required this.mediaSizeBytes,
    required this.status,
    required this.phase,
    required this.createdAt,
    required this.updatedAt,
    this.mediaPath,
    this.mediaMimeType,
    this.mediaFileName,
    this.thumbnailPath,
    this.caption,
    this.textContent,
    this.privacy = StoryPrivacy.contacts,
    this.customPrivacyList,
    this.uploadedBytes = 0,
    this.totalBytes = 0,
    this.attempts = 0,
    this.maxAttempts = 3,
    this.nextRetryAt,
    this.error,
  });

  double? get progress {
    if (totalBytes > 0) {
      return (uploadedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
    }
    return switch (phase) {
      StoryCreationPhase.uploadingThumbnail => 0.9,
      StoryCreationPhase.publishing => 0.95,
      StoryCreationPhase.preparing || StoryCreationPhase.uploadingMedia => null,
    };
  }

  bool get isVisible =>
      status == StoryUploadStatus.queued ||
      status == StoryUploadStatus.running ||
      status == StoryUploadStatus.failed;

  bool get shouldAutoRetry =>
      status == StoryUploadStatus.failed &&
      attempts < maxAttempts &&
      nextRetryAt != null;

  StoryUploadJob copyWith({
    StoryUploadStatus? status,
    StoryCreationPhase? phase,
    int? uploadedBytes,
    int? totalBytes,
    int? attempts,
    DateTime? updatedAt,
    DateTime? nextRetryAt,
    String? error,
    bool clearRetryAt = false,
    bool clearError = false,
  }) {
    return StoryUploadJob(
      id: id,
      ownerUserId: ownerUserId,
      mediaType: mediaType,
      mediaPath: mediaPath,
      mediaSizeBytes: mediaSizeBytes,
      mediaMimeType: mediaMimeType,
      mediaFileName: mediaFileName,
      thumbnailPath: thumbnailPath,
      caption: caption,
      textContent: textContent,
      privacy: privacy,
      customPrivacyList: customPrivacyList,
      status: status ?? this.status,
      phase: phase ?? this.phase,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      nextRetryAt: clearRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
      error: clearError ? null : error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerUserId': ownerUserId,
    'mediaType': mediaType.name,
    'mediaPath': mediaPath,
    'mediaSizeBytes': mediaSizeBytes,
    'mediaMimeType': mediaMimeType,
    'mediaFileName': mediaFileName,
    'thumbnailPath': thumbnailPath,
    'caption': caption,
    'textContent': textContent,
    'privacy': privacy.name,
    'customPrivacyList': customPrivacyList,
    'status': status.name,
    'phase': phase.name,
    'uploadedBytes': uploadedBytes,
    'totalBytes': totalBytes,
    'attempts': attempts,
    'maxAttempts': maxAttempts,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'nextRetryAt': nextRetryAt?.toIso8601String(),
    'error': error,
  };

  factory StoryUploadJob.fromJson(Map<dynamic, dynamic> json) {
    T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
      if (name is! String) return fallback;
      return values.firstWhere(
        (value) => value.name == name,
        orElse: () => fallback,
      );
    }

    final restoredStatus = enumByName(
      StoryUploadStatus.values,
      json['status'],
      StoryUploadStatus.queued,
    );
    return StoryUploadJob(
      id: json['id'] as String,
      ownerUserId: json['ownerUserId'] as String? ?? 'legacy',
      mediaType: enumByName(
        StoryMediaType.values,
        json['mediaType'],
        StoryMediaType.text,
      ),
      mediaPath: json['mediaPath'] as String?,
      mediaSizeBytes: (json['mediaSizeBytes'] as num?)?.toInt() ?? 0,
      mediaMimeType: json['mediaMimeType'] as String?,
      mediaFileName: json['mediaFileName'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      caption: json['caption'] as String?,
      textContent: json['textContent'] as String?,
      privacy: enumByName(
        StoryPrivacy.values,
        json['privacy'],
        StoryPrivacy.contacts,
      ),
      customPrivacyList: (json['customPrivacyList'] as List?)
          ?.whereType<String>()
          .toList(growable: false),
      status: restoredStatus == StoryUploadStatus.running
          ? StoryUploadStatus.queued
          : restoredStatus,
      phase: enumByName(
        StoryCreationPhase.values,
        json['phase'],
        StoryCreationPhase.preparing,
      ),
      uploadedBytes: (json['uploadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 3,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      nextRetryAt: DateTime.tryParse(json['nextRetryAt'] as String? ?? ''),
      error: json['error'] == null
          ? null
          : userFacingError(
              json['error'],
              fallback: 'Story upload failed. Please retry.',
            ),
    );
  }
}

class StoryUploadQueueService {
  static final StoryUploadQueueService instance = StoryUploadQueueService._();
  StoryUploadQueueService._();

  static const String boxName = 'xmo_story_upload_queue';

  Box? _box;
  StoryService? _storyService;
  String? _ownerUserId;
  ValueChanged<Story>? _onStoryCreated;
  final Map<String, StoryUploadJob> _jobs = {};
  final Set<String> _runningIds = {};
  final Set<String> _explicitlyCancelledIds = {};
  final Map<String, StoryCreationCancellationToken> _cancellationTokens = {};
  final Map<String, Timer> _retryTimers = {};
  final Map<String, int> _lastPersistedProgressBytes = {};
  final Map<String, DateTime> _lastPersistedProgressAt = {};
  final _controller = StreamController<List<StoryUploadJob>>.broadcast();
  final _completionController = StreamController<Story>.broadcast();

  Stream<List<StoryUploadJob>> get stream => _controller.stream;
  Stream<Story> get completedStories => _completionController.stream;
  List<StoryUploadJob> get jobs => List.unmodifiable(_jobs.values);

  Future<void> attach(
    StoryService storyService, {
    ValueChanged<Story>? onStoryCreated,
  }) async {
    _storyService = storyService;
    if (onStoryCreated != null) _onStoryCreated = onStoryCreated;
    await setCurrentUser(storyService.currentUserId);
    _resumePendingJobs();
  }

  Future<void> init() async {
    if (_box != null) return;
    _box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await Hive.openBox(boxName);
    _loadPersistedJobs();
  }

  Future<void> setCurrentUser(String? userId) async {
    await init();
    final normalized = userId?.trim();
    if (_ownerUserId == normalized) {
      _resumePendingJobs();
      return;
    }
    for (final token in _cancellationTokens.values) {
      token.cancel();
    }
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _cancellationTokens.clear();
    _retryTimers.clear();
    _ownerUserId = normalized;
    _loadPersistedJobs();
    _resumePendingJobs();
  }

  Future<StoryUploadJob> enqueue(CreateStoryRequest request) async {
    await init();
    final storyService = _storyService;
    if (storyService == null) {
      throw StateError('The story upload service is not ready');
    }
    storyService.validateCreateRequest(request);
    final ownerUserId = _activeOwnerUserId;
    if (ownerUserId == 'legacy') {
      throw StateError('A logged-in account is required to upload a story');
    }
    final id = request.clientRequestId?.trim();
    if (id == null || id.isEmpty) {
      throw ArgumentError('A story upload requires a client request ID');
    }
    final existing = _jobs[id];
    if (existing != null) return existing;

    final directory = await _queueDirectory();
    final fileStem = _safeFileStem(id);
    String? mediaPath;
    String? thumbnailPath;
    try {
      if (request.mediaFilePath != null) {
        final source = File(request.mediaFilePath!);
        if (!await source.exists()) {
          throw const StoryValidationException(
            'Story media is no longer available',
          );
        }
        mediaPath = '${directory.path}${Platform.pathSeparator}$fileStem.media';
        await source.copy(mediaPath);
      } else if (request.mediaBytes != null && request.mediaBytes!.isNotEmpty) {
        mediaPath = '${directory.path}${Platform.pathSeparator}$fileStem.media';
        await File(mediaPath).writeAsBytes(request.mediaBytes!, flush: true);
      }
      if (request.thumbnailBytes != null &&
          request.thumbnailBytes!.isNotEmpty) {
        thumbnailPath =
            '${directory.path}${Platform.pathSeparator}$fileStem.thumbnail';
        await File(
          thumbnailPath,
        ).writeAsBytes(request.thumbnailBytes!, flush: true);
      }

      final mediaSizeBytes = mediaPath == null
          ? 0
          : await File(mediaPath).length();
      final now = DateTime.now();
      final job = StoryUploadJob(
        id: id,
        ownerUserId: ownerUserId,
        mediaType: request.mediaType,
        mediaPath: mediaPath,
        mediaSizeBytes: mediaSizeBytes,
        mediaMimeType: request.mediaMimeType,
        mediaFileName: request.mediaFileName,
        thumbnailPath: thumbnailPath,
        caption: request.caption,
        textContent: request.textContent,
        privacy: request.privacy,
        customPrivacyList: request.customPrivacyList == null
            ? null
            : List<String>.unmodifiable(request.customPrivacyList!),
        status: StoryUploadStatus.queued,
        phase: StoryCreationPhase.preparing,
        createdAt: now,
        updatedAt: now,
      );
      await _save(job);
      unawaited(_run(job.id));
      return job;
    } catch (_) {
      await _deleteFile(mediaPath);
      await _deleteFile(thumbnailPath);
      rethrow;
    }
  }

  Future<void> retry(String id) async {
    final job = _jobs[id];
    if (job == null || job.status != StoryUploadStatus.failed) return;
    _retryTimers.remove(id)?.cancel();
    await _save(
      job.copyWith(
        status: StoryUploadStatus.queued,
        phase: StoryCreationPhase.preparing,
        uploadedBytes: 0,
        totalBytes: 0,
        clearError: true,
        clearRetryAt: true,
      ),
    );
    unawaited(_run(id));
  }

  Future<void> cancel(String id) async {
    _explicitlyCancelledIds.add(id);
    _cancellationTokens[id]?.cancel();
    _retryTimers.remove(id)?.cancel();
    final job = _jobs[id];
    if (job == null) return;
    final wasRunning = _runningIds.contains(id);
    await _save(
      job.copyWith(status: StoryUploadStatus.cancelled, clearRetryAt: true),
    );
    await _remove(id);
    if (!wasRunning) {
      await _deletePayloadFiles(job);
      _explicitlyCancelledIds.remove(id);
    }
  }

  Future<void> discardCurrentUserJobs() async {
    for (final id in _jobs.keys.toList(growable: false)) {
      await cancel(id);
    }
  }

  void _resumePendingJobs() {
    if (_storyService == null || _ownerUserId == null) return;
    for (final job in _jobs.values.toList(growable: false)) {
      if (job.status == StoryUploadStatus.queued) {
        unawaited(_run(job.id));
      } else if (job.shouldAutoRetry) {
        _scheduleRetry(job);
      }
    }
  }

  Future<void> _run(String id) async {
    final service = _storyService;
    final initialJob = _jobs[id];
    if (service == null ||
        initialJob == null ||
        initialJob.ownerUserId != _activeOwnerUserId ||
        initialJob.status != StoryUploadStatus.queued ||
        !_runningIds.add(id)) {
      return;
    }

    final token = StoryCreationCancellationToken();
    _cancellationTokens[id] = token;
    final runningJob = initialJob.copyWith(
      status: StoryUploadStatus.running,
      phase: StoryCreationPhase.preparing,
      attempts: initialJob.attempts + 1,
      uploadedBytes: 0,
      totalBytes: 0,
      clearError: true,
      clearRetryAt: true,
    );
    await _save(runningJob);

    try {
      final thumbnailBytes = await _readOptionalBytes(runningJob.thumbnailPath);
      final request = CreateStoryRequest(
        clientRequestId: runningJob.id,
        mediaType: runningJob.mediaType,
        mediaFilePath: runningJob.mediaPath,
        mediaSizeBytes: runningJob.mediaPath == null
            ? null
            : runningJob.mediaSizeBytes,
        mediaMimeType: runningJob.mediaMimeType,
        mediaFileName: runningJob.mediaFileName,
        thumbnailBytes: thumbnailBytes,
        caption: runningJob.caption,
        textContent: runningJob.textContent,
        privacy: runningJob.privacy,
        customPrivacyList: runningJob.customPrivacyList,
      );
      final story = await service.createStory(
        request,
        cancellationToken: token,
        onProgress: (progress) => _updateProgress(id, progress),
      );
      if (token.isCancelled || _jobs[id] == null) return;
      await _save(
        (_jobs[id] ?? runningJob).copyWith(
          status: StoryUploadStatus.completed,
          phase: StoryCreationPhase.publishing,
          uploadedBytes: runningJob.mediaSizeBytes,
          totalBytes: runningJob.mediaSizeBytes,
          clearError: true,
          clearRetryAt: true,
        ),
      );
      try {
        _onStoryCreated?.call(story);
      } catch (error) {
        debugPrint('[StoryUploadQueue] Completion callback failed: $error');
      }
      if (!_completionController.isClosed) {
        _completionController.add(story);
      }
      await _deletePayloadFiles(runningJob);
      await _remove(id);
    } on StoryCreationCancelledException {
      final current = _jobs[id];
      if (_explicitlyCancelledIds.contains(id) &&
          current?.ownerUserId == runningJob.ownerUserId) {
        await cancel(id);
      }
    } catch (error) {
      final current = _jobs[id];
      if (current == null || token.isCancelled) return;
      final retryAt = current.attempts < current.maxAttempts
          ? DateTime.now().add(_retryDelay(current.attempts))
          : null;
      final failed = current.copyWith(
        status: StoryUploadStatus.failed,
        error: _shortError(error),
        nextRetryAt: retryAt,
      );
      await _save(failed);
      if (failed.shouldAutoRetry) _scheduleRetry(failed);
    } finally {
      if (_explicitlyCancelledIds.remove(id)) {
        await _deletePayloadFiles(runningJob);
      }
      _runningIds.remove(id);
      _cancellationTokens.remove(id);
      _lastPersistedProgressBytes.remove(id);
      _lastPersistedProgressAt.remove(id);
      final resumable = _jobs[id];
      if (resumable?.ownerUserId == _activeOwnerUserId &&
          resumable?.status == StoryUploadStatus.queued) {
        unawaited(_run(id));
      }
    }
  }

  void _updateProgress(String id, StoryCreationProgress progress) {
    final job = _jobs[id];
    if (job == null || job.status != StoryUploadStatus.running) return;
    final updated = job.copyWith(
      phase: progress.phase,
      uploadedBytes: progress.uploadedBytes,
      totalBytes: progress.totalBytes,
    );
    final now = DateTime.now();
    final previousBytes = _lastPersistedProgressBytes[id] ?? 0;
    final previousAt = _lastPersistedProgressAt[id];
    final shouldPersist =
        progress.phase != StoryCreationPhase.uploadingMedia ||
        (progress.uploadedBytes - previousBytes).abs() >= 256 * 1024 ||
        previousAt == null ||
        now.difference(previousAt) >= const Duration(seconds: 1);
    if (shouldPersist) {
      _lastPersistedProgressBytes[id] = progress.uploadedBytes;
      _lastPersistedProgressAt[id] = now;
    }
    unawaited(_save(updated, persistImmediately: shouldPersist));
  }

  void _scheduleRetry(StoryUploadJob job) {
    final retryAt = job.nextRetryAt;
    if (retryAt == null || _retryTimers.containsKey(job.id)) return;
    final delay = retryAt.difference(DateTime.now());
    _retryTimers[job.id] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () async {
        _retryTimers.remove(job.id);
        final current = _jobs[job.id];
        if (current?.shouldAutoRetry != true) return;
        await retry(job.id);
      },
    );
  }

  Duration _retryDelay(int attempts) {
    final exponent = (attempts - 1).clamp(0, 2).toInt();
    final seconds = 2 * (1 << exponent);
    return Duration(seconds: seconds.clamp(2, 8).toInt());
  }

  Future<void> _save(
    StoryUploadJob job, {
    bool persistImmediately = true,
  }) async {
    if (job.ownerUserId != _activeOwnerUserId) return;
    _jobs[job.id] = job;
    if (persistImmediately) {
      await _box?.put(_storageKey(job.ownerUserId, job.id), job.toJson());
    }
    _emit();
  }

  Future<void> _remove(String id) async {
    final job = _jobs.remove(id);
    if (job != null) {
      await _box?.delete(_storageKey(job.ownerUserId, id));
    }
    _emit();
  }

  void _loadPersistedJobs() {
    _jobs.clear();
    for (final key in _box?.keys ?? const []) {
      final raw = _box?.get(key);
      if (raw is! Map) continue;
      try {
        final job = StoryUploadJob.fromJson(raw);
        if (job.ownerUserId != _activeOwnerUserId) continue;
        if (job.status == StoryUploadStatus.completed ||
            job.status == StoryUploadStatus.cancelled) {
          unawaited(_deletePayloadFiles(job));
          unawaited(_box?.delete(key) ?? Future<void>.value());
          continue;
        }
        _jobs[job.id] = job;
      } catch (error) {
        debugPrint('[StoryUploadQueue] Failed to restore $key: $error');
      }
    }
    _emit();
  }

  String get _activeOwnerUserId => _ownerUserId ?? 'legacy';

  String _storageKey(String ownerUserId, String id) => '$ownerUserId::$id';

  String _safeFileStem(String id) {
    final sanitized = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.length <= 180 ? sanitized : sanitized.substring(0, 180);
  }

  Future<Directory> _queueDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}xmo_story_upload_queue',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Uint8List?> _readOptionalBytes(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> _deletePayloadFiles(StoryUploadJob job) async {
    await _deleteFile(job.mediaPath);
    await _deleteFile(job.thumbnailPath);
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[StoryUploadQueue] Failed to delete $path: $error');
    }
  }

  String _shortError(Object error) {
    return userFacingError(
      error,
      fallback: 'Story upload failed. Please retry.',
    );
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(jobs);
  }
}
