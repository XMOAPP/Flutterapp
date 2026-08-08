import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:matrix/matrix.dart';
import '../models/story_models.dart';
import '../utils/matrix_identity.dart';
import 'matrix_service.dart';
import 'privacy_service.dart';

/// Service for managing Stories feature
class StoryService {
  final MatrixService _matrixService;

  StoryService(this._matrixService);

  Client get _client => _matrixService.client;
  Stream<EventUpdate> get onEvent => _matrixService.onEvent;
  Stream<BasicEvent> get onAccountData => _client.onAccountData.stream;
  String? get currentUserId => _client.userID;

  // Custom event type for stories
  static const String storyAccountDataType = 'xmo.user.stories';
  static const String storyUpdateEventType = 'xmo.story.update';
  static const String storyViewEventType = 'xmo.story.view';
  static const String viewedStoriesAccountDataKey = 'xmo.user.viewed_stories';
  static const String _sentStoryViewReceiptsAccountDataKey =
      'xmo.user.story_view_receipts';
  static const String _storyCacheBoxName = 'xmo_story_timeline_cache';
  static const String _storyBroadcastOutboxPrefix = 'story_broadcast_outbox::';
  static const Duration _storyDuration = Duration(hours: 24);
  static const Duration _storyViewHistoryGrace = Duration(minutes: 5);
  static const int _storyViewHistoryPageSize = 100;
  static const int _storyViewHistoryMaxPages = 4;
  static const int _maxStoredViewReceiptsPerOwner = 256;
  static const int _maxStoriesPerSnapshot = 100;
  static const int _maxImageBytes = 25 * 1024 * 1024;
  static const int _maxVideoBytes = 250 * 1024 * 1024;
  static const int _maxThumbnailBytes = 5 * 1024 * 1024;
  static const int _maxUploadAttempts = 3;
  static const int _maxBroadcastAttempts = 8;

  final Set<String> _pendingStoryViewReceipts = <String>{};
  bool _retryingStoryBroadcast = false;

  Future<Box> _storyCacheBox() async {
    if (Hive.isBoxOpen(_storyCacheBoxName)) {
      return Hive.box(_storyCacheBoxName);
    }
    return Hive.openBox(_storyCacheBoxName);
  }

  String? get _storyCacheKey {
    final userId = _client.userID;
    if (userId == null || userId.isEmpty) return null;
    return 'contact_stories::$userId';
  }

  String? get _storyBroadcastOutboxKey {
    final userId = _client.userID;
    if (userId == null || userId.isEmpty) return null;
    return '$_storyBroadcastOutboxPrefix$userId';
  }

  /// Restores the last known story update events and local viewed state. This
  /// is deliberately local: network timeline scanning happens only for an
  /// initial cache miss or an explicit refresh, while new Matrix events keep
  /// the cache current.
  Future<List<UserStories>> loadCachedContactStories() async {
    final key = _storyCacheKey;
    if (key == null) return const [];
    try {
      final raw = (await _storyCacheBox()).get(key);
      if (raw is! List) return const [];
      final stories = raw
          .whereType<Map>()
          .map(
            (item) => _userStoriesFromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((item) => item.hasActiveStories)
          .toList();
      stories.sort((a, b) {
        final aLatest = a.latestStory?.createdAt ?? DateTime(0);
        final bLatest = b.latestStory?.createdAt ?? DateTime(0);
        return bLatest.compareTo(aLatest);
      });
      return stories;
    } catch (e) {
      debugPrint('[StoryService] Failed to restore story cache: $e');
      return const [];
    }
  }

  Future<void> cacheContactStories(List<UserStories> stories) async {
    final key = _storyCacheKey;
    if (key == null) return;
    try {
      await (await _storyCacheBox()).put(
        key,
        stories
            .where((item) => item.hasActiveStories)
            .map(_userStoriesToJson)
            .toList(),
      );
    } catch (e) {
      debugPrint('[StoryService] Failed to persist story cache: $e');
    }
  }

  Map<String, dynamic> _userStoriesToJson(UserStories stories) => {
    'userId': stories.userId,
    'userName': stories.userName,
    'userAvatarUrl': stories.userAvatarUrl,
    'snapshotUpdatedAt': stories.snapshotUpdatedAt?.millisecondsSinceEpoch,
    // Story IDs and viewedBy are retained by Story.toJson().
    'stories': stories.stories.map((story) => story.toJson()).toList(),
  };

  UserStories _userStoriesFromJson(Map<String, dynamic> json) {
    final userId = _safeString(json['userId'], Story.maxUserIdLength);
    final userName = _safeString(json['userName'], Story.maxUserNameLength);
    return UserStories(
      userId: userId ?? '',
      userName: MatrixIdentity.displayName(
        userId: userId ?? '',
        candidate: userName,
      ),
      userAvatarUrl: _safeOptionalString(
        json['userAvatarUrl'],
        Story.maxUrlLength,
      ),
      snapshotUpdatedAt: _dateTimeFromMilliseconds(json['snapshotUpdatedAt']),
      stories: _parseStoryList(json['stories'], expectedOwnerId: userId),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CREATE STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validates a Story request before it is staged for background upload.
  void validateCreateRequest(CreateStoryRequest request) {
    _validateCreateRequest(request);
  }

  /// Creates a new story
  Future<Story> createStory(
    CreateStoryRequest request, {
    ValueChanged<StoryCreationProgress>? onProgress,
    StoryCreationCancellationToken? cancellationToken,
  }) async {
    final myUserId = _client.userID;
    if (myUserId == null) throw Exception('User not logged in');
    _validateCreateRequest(request);
    _throwIfStoryCreationCancelled(cancellationToken);
    final storyId = request.clientRequestId?.trim() ?? _generateStoryId();

    // A publish response can be lost after account data was committed. Reusing
    // the creator's request ID makes that retry return the durable Story
    // instead of uploading the media and appending a duplicate.
    if (request.clientRequestId != null) {
      final existingStories = await getMyStories(includeRemoteViews: false);
      for (final existingStory in existingStories) {
        if (existingStory.id == storyId) {
          await retryPendingStoryDistribution();
          return existingStory;
        }
      }
    }
    onProgress?.call(
      const StoryCreationProgress(phase: StoryCreationPhase.preparing),
    );

    String? mediaUrl;
    String? thumbnailUrl;
    final profile = await _getProfileSafely(myUserId);

    // Upload media if provided
    if (request.mediaFilePath != null) {
      mediaUrl = await _uploadStoryMediaFile(
        request.mediaFilePath!,
        filename: request.mediaFileName,
        contentType: request.mediaMimeType,
        onProgress: (uploaded, total) => onProgress?.call(
          StoryCreationProgress(
            phase: StoryCreationPhase.uploadingMedia,
            uploadedBytes: uploaded,
            totalBytes: total,
          ),
        ),
        cancellationToken: cancellationToken,
      );
    } else if (request.mediaBytes != null) {
      mediaUrl = await _uploadStoryMedia(
        request.mediaBytes!,
        filename: request.mediaFileName,
        contentType: request.mediaMimeType,
        onProgress: (uploaded, total) => onProgress?.call(
          StoryCreationProgress(
            phase: StoryCreationPhase.uploadingMedia,
            uploadedBytes: uploaded,
            totalBytes: total,
          ),
        ),
        cancellationToken: cancellationToken,
      );
    }

    if (request.thumbnailBytes != null && request.thumbnailBytes!.isNotEmpty) {
      onProgress?.call(
        const StoryCreationProgress(
          phase: StoryCreationPhase.uploadingThumbnail,
        ),
      );
      thumbnailUrl = await _uploadStoryMedia(
        request.thumbnailBytes!,
        filename: 'story_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: 'image/jpeg',
        cancellationToken: cancellationToken,
      );
    }
    _throwIfStoryCreationCancelled(cancellationToken);

    // Create story object
    final now = DateTime.now();
    final story = Story(
      id: storyId,
      userId: myUserId,
      userName: MatrixIdentity.displayName(
        userId: myUserId,
        candidate: profile?.displayName,
      ),
      userAvatarUrl: profile?.avatarUrl?.toString(),
      mediaUrl: mediaUrl,
      mediaMimeType: request.mediaMimeType,
      thumbnailUrl: thumbnailUrl,
      mediaType: request.mediaType,
      caption: request.caption,
      textContent: request.textContent,
      createdAt: now,
      expiresAt: now.add(_storyDuration),
      viewedBy: [],
      privacy: request.privacy,
      customPrivacyList: request.customPrivacyList,
    );

    // Save story to account data
    onProgress?.call(
      const StoryCreationProgress(phase: StoryCreationPhase.publishing),
    );
    await _saveStoryToAccountData(story);

    debugPrint('[StoryService] Created story: ${story.id}');
    return story;
  }

  /// Upload story media to Matrix media repository
  Future<String> _uploadStoryMedia(
    Uint8List bytes, {
    String? filename,
    String? contentType,
    void Function(int uploadedBytes, int totalBytes)? onProgress,
    StoryCreationCancellationToken? cancellationToken,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxUploadAttempts; attempt++) {
      try {
        _throwIfStoryCreationCancelled(cancellationToken);
        final uri = onProgress == null && cancellationToken == null
            ? await _client.uploadContent(
                bytes,
                filename:
                    filename ??
                    'story_${DateTime.now().millisecondsSinceEpoch}',
                contentType: contentType,
              )
            : await _matrixService.uploadBytesWithProgress(
                bytes,
                filename:
                    filename ??
                    'story_${DateTime.now().millisecondsSinceEpoch}',
                contentType: contentType,
                onProgress: onProgress,
                isCancelled: () => cancellationToken?.isCancelled ?? false,
              );
        return uri.toString();
      } on MatrixUploadCancelledException {
        throw const StoryCreationCancelledException();
      } on StoryCreationCancelledException {
        rethrow;
      } catch (error) {
        lastError = error;
        debugPrint(
          '[StoryService] Media upload attempt $attempt failed: '
          '${error.runtimeType}',
        );
        if (attempt < _maxUploadAttempts) {
          await Future<void>.delayed(
            Duration(milliseconds: 300 * attempt * attempt),
          );
        }
      }
    }
    throw StoryUploadException(lastError);
  }

  Future<String> _uploadStoryMediaFile(
    String filePath, {
    String? filename,
    String? contentType,
    void Function(int uploadedBytes, int totalBytes)? onProgress,
    StoryCreationCancellationToken? cancellationToken,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxUploadAttempts; attempt++) {
      try {
        _throwIfStoryCreationCancelled(cancellationToken);
        final uri = await _matrixService.uploadFileContentWithProgress(
          filePath,
          filename:
              filename ?? 'story_${DateTime.now().millisecondsSinceEpoch}',
          contentType: contentType,
          onProgress: onProgress,
          isCancelled: () => cancellationToken?.isCancelled ?? false,
        );
        return uri.toString();
      } on MatrixUploadCancelledException {
        throw const StoryCreationCancelledException();
      } on StoryCreationCancelledException {
        rethrow;
      } catch (error) {
        lastError = error;
        debugPrint(
          '[StoryService] Media upload attempt $attempt failed: '
          '${error.runtimeType}',
        );
        if (attempt < _maxUploadAttempts) {
          await Future<void>.delayed(
            Duration(milliseconds: 300 * attempt * attempt),
          );
        }
      }
    }
    throw StoryUploadException(lastError);
  }

  void _throwIfStoryCreationCancelled(
    StoryCreationCancellationToken? cancellationToken,
  ) {
    if (cancellationToken?.isCancelled ?? false) {
      throw const StoryCreationCancelledException();
    }
  }

  /// Generate unique story ID
  String _generateStoryId() {
    return 'story_${DateTime.now().millisecondsSinceEpoch}_${_client.userID?.hashCode ?? 0}';
  }

  /// Save story to Matrix account data and broadcast to direct chat rooms
  Future<void> _saveStoryToAccountData(Story story) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return;

      // Get existing stories
      final existingStories = await getMyStories();

      // Replace the same idempotent publish instead of appending a duplicate.
      existingStories.removeWhere((existing) => existing.id == story.id);
      existingStories.add(story);

      // Remove expired stories
      final activeStories = existingStories.where((s) => !s.isExpired).toList();

      // Save to account data (for our own reference)
      final storiesJson = activeStories.map((s) => s.toJson()).toList();
      await _client.setAccountData(myUserId, storyAccountDataType, {
        'stories': storiesJson,
      });

      // Broadcast to all allowed direct chat rooms so contacts can see our
      // stories. The story is already durable in account data at this point;
      // failed room deliveries are retained for bounded background retries.
      await _publishStorySnapshot(activeStories);
    } catch (e) {
      debugPrint('[StoryService] Failed to save story: $e');
      rethrow;
    }
  }

  /// Broadcast stories to all direct chat rooms
  /// Uses regular events instead of state events for better compatibility
  Future<Set<String>> _broadcastStoriesToContacts(
    List<Story> stories, {
    Set<String>? targetRoomIds,
    required int snapshotUpdatedAt,
  }) async {
    final failedRoomIds = <String>{};
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return failedRoomIds;

      // Get all direct chat rooms
      final directRooms = _client.rooms.where(
        (room) =>
            room.isDirectChat &&
            (targetRoomIds == null || targetRoomIds.contains(room.id)),
      );

      // Send event to each direct chat room
      for (final room in directRooms) {
        try {
          final viewerId =
              _matrixService.getDirectPeerUserId(room) ??
              room.directChatMatrixID;
          if (viewerId == null || viewerId == myUserId) continue;

          final visibleStories = stories
              .where((story) => canDirectContactViewStory(story, viewerId))
              .toList();
          final storiesJson = visibleStories.map((s) => s.toJson()).toList();

          await room.sendEvent({
            'msgtype': storyUpdateEventType,
            'user_id': myUserId,
            'stories': storiesJson,
            'updated_at': snapshotUpdatedAt,
          }, type: storyUpdateEventType);
          debugPrint('[StoryService] Broadcasted stories to room ${room.id}');
        } catch (e) {
          failedRoomIds.add(room.id);
          debugPrint(
            '[StoryService] Failed to broadcast to room ${room.id}: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('[StoryService] Failed to broadcast stories: $e');
      if (targetRoomIds != null) failedRoomIds.addAll(targetRoomIds);
    }
    return failedRoomIds;
  }

  Future<void> _publishStorySnapshot(List<Story> stories) async {
    final snapshotUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    final failedRoomIds = await _broadcastStoriesToContacts(
      stories,
      snapshotUpdatedAt: snapshotUpdatedAt,
    );
    await _saveStoryBroadcastOutbox(
      stories: stories,
      failedRoomIds: failedRoomIds,
      snapshotUpdatedAt: snapshotUpdatedAt,
      attempts: 0,
    );
  }

  Future<void> _saveStoryBroadcastOutbox({
    required List<Story> stories,
    required Set<String> failedRoomIds,
    required int snapshotUpdatedAt,
    required int attempts,
  }) async {
    final key = _storyBroadcastOutboxKey;
    if (key == null) return;
    try {
      final box = await _storyCacheBox();
      if (failedRoomIds.isEmpty || attempts >= _maxBroadcastAttempts) {
        await box.delete(key);
        if (attempts >= _maxBroadcastAttempts && failedRoomIds.isNotEmpty) {
          debugPrint(
            '[StoryService] Story distribution stopped after '
            '$attempts attempts for ${failedRoomIds.length} room(s)',
          );
        }
        return;
      }

      final exponent = attempts.clamp(0, 7).toInt();
      final delaySeconds = (1 << exponent) * 5;
      await box.put(key, {
        'stories': stories.map((story) => story.toJson()).toList(),
        'room_ids': failedRoomIds.toList(),
        'updated_at': snapshotUpdatedAt,
        'attempts': attempts,
        'next_attempt_at': DateTime.now()
            .add(Duration(seconds: delaySeconds))
            .millisecondsSinceEpoch,
      });
    } catch (error) {
      // Account data is the durable source of truth. Retry bookkeeping must
      // never make a successfully published Story appear to have failed.
      debugPrint(
        '[StoryService] Failed to persist Story distribution retry: '
        '${error.runtimeType}',
      );
    }
  }

  /// Retries only failed direct-room deliveries from the latest Story
  /// snapshot. A newer publish replaces this record, so stale snapshots never
  /// overtake newer Story state.
  Future<void> retryPendingStoryDistribution() async {
    if (_retryingStoryBroadcast) return;
    final key = _storyBroadcastOutboxKey;
    final myUserId = _client.userID;
    if (key == null || myUserId == null) return;

    _retryingStoryBroadcast = true;
    try {
      final box = await _storyCacheBox();
      final raw = box.get(key);
      if (raw is! Map) return;
      final data = raw.map((key, value) => MapEntry(key.toString(), value));
      final nextAttemptAt = _intFromDynamic(data['next_attempt_at']);
      if (nextAttemptAt != null &&
          DateTime.now().millisecondsSinceEpoch < nextAttemptAt) {
        return;
      }

      final stories = _parseStoryList(
        data['stories'],
        expectedOwnerId: myUserId,
      );
      final roomIds =
          (data['room_ids'] as List?)
              ?.whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet() ??
          <String>{};
      final snapshotUpdatedAt = _intFromDynamic(data['updated_at']);
      final attempts = _intFromDynamic(data['attempts']) ?? 0;
      if (roomIds.isEmpty || snapshotUpdatedAt == null) {
        await box.delete(key);
        return;
      }

      // Rooms that are no longer active direct chats are intentionally
      // dropped; they cannot receive this snapshot and should not keep the
      // outbox alive.
      final activeRoomIds = _client.rooms
          .where((room) => room.isDirectChat && roomIds.contains(room.id))
          .map((room) => room.id)
          .toSet();
      if (activeRoomIds.isEmpty) {
        await box.delete(key);
        return;
      }

      final failedRoomIds = await _broadcastStoriesToContacts(
        stories,
        targetRoomIds: activeRoomIds,
        snapshotUpdatedAt: snapshotUpdatedAt,
      );
      await _saveStoryBroadcastOutbox(
        stories: stories,
        failedRoomIds: failedRoomIds,
        snapshotUpdatedAt: snapshotUpdatedAt,
        attempts: attempts + 1,
      );
    } catch (error) {
      debugPrint(
        '[StoryService] Failed to retry Story distribution: '
        '${error.runtimeType}',
      );
    } finally {
      _retryingStoryBroadcast = false;
    }
  }

  int? _intFromDynamic(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GET STORIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get my stories
  Future<List<Story>> getMyStories({bool includeRemoteViews = true}) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return [];

      final accountData = await _client.getAccountData(
        myUserId,
        storyAccountDataType,
      );

      final stories = _parseStoryList(
        accountData['stories'],
        expectedOwnerId: myUserId,
      ).where((story) => !story.isExpired).toList();

      final enrichedStories = await _applyOwnProfileToStories(stories);
      return includeRemoteViews
          ? await _applyRemoteViewsToOwnedStories(enrichedStories)
          : enrichedStories;
    } catch (e) {
      debugPrint('[StoryService] Failed to get my stories: $e');
      return [];
    }
  }

  /// Get stories from a specific user
  /// Stories are broadcasted as timeline events in direct chat rooms
  Future<List<Story>> getUserStories(String userId) async {
    final snapshot = await _getUserStoriesSnapshot(userId);
    return snapshot?.stories ?? const [];
  }

  Future<UserStories?> _getUserStoriesSnapshot(String userId) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return null;

      // If it's our own stories, read from account data
      if (userId == myUserId) {
        final stories = await getMyStories();
        return UserStories(
          userId: userId,
          userName: MatrixIdentity.displayName(
            userId: userId,
            candidate: stories.isNotEmpty ? stories.first.userName : null,
          ),
          userAvatarUrl: stories.isNotEmpty
              ? stories.first.userAvatarUrl
              : null,
          stories: stories,
        );
      }

      // For other users, find the direct chat room and look for story update events
      final directRoom = _client.rooms.firstWhere(
        (r) => r.isDirectChat && r.directChatMatrixID == userId,
        orElse: () => throw Exception('No direct chat found'),
      );

      // Matrix does not guarantee that delayed sync updates arrive in the same
      // order as these full-list story snapshots were created.
      final timeline = await directRoom.getTimeline();

      Event? latestStoryEvent;
      var latestVersion = -1;
      for (final event in timeline.events) {
        if (event.type != storyUpdateEventType ||
            event.content['user_id'] != userId) {
          continue;
        }
        final version = _storyEventVersion(event);
        if (latestStoryEvent == null || version > latestVersion) {
          latestStoryEvent = event;
          latestVersion = version;
        }
      }

      if (latestStoryEvent == null) return null;

      return await buildUserStoriesFromUpdateContent({
        'type': latestStoryEvent.type,
        'sender': latestStoryEvent.senderId,
        'content': latestStoryEvent.content,
        'origin_server_ts':
            latestStoryEvent.originServerTs.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[StoryService] Failed to get user stories for $userId: $e');
      return null;
    }
  }

  /// Get all stories from contacts (users in direct chats)
  Future<List<UserStories>> getAllContactStories() async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return [];

      final allUserStories = <UserStories>[];

      // Get all direct chat rooms
      final directRooms = _client.rooms.where((r) => r.isDirectChat);

      // Get unique contact user IDs
      final contactUserIds = <String>{};
      for (final room in directRooms) {
        final otherUserId = room.directChatMatrixID;
        if (otherUserId != null && otherUserId != myUserId) {
          contactUserIds.add(otherUserId);
        }
      }

      // Fetch stories for each contact
      for (final userId in contactUserIds) {
        try {
          final userStories = await _getUserStoriesSnapshot(userId);
          if (userStories?.hasActiveStories ?? false) {
            allUserStories.add(userStories!);
          }
        } catch (e) {
          debugPrint('[StoryService] Failed to get stories for $userId: $e');
        }
      }

      // Sort by latest story time
      allUserStories.sort((a, b) {
        final aLatest = a.latestStory?.createdAt ?? DateTime(0);
        final bLatest = b.latestStory?.createdAt ?? DateTime(0);
        return bLatest.compareTo(aLatest);
      });

      return allUserStories;
    } catch (e) {
      debugPrint('[StoryService] Failed to get all contact stories: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> applyPrivacySettingsToMyStories(
    XmoPrivacySettings settings,
  ) async {
    final myUserId = _client.userID;
    if (myUserId == null) return;

    final privacy = switch (settings.storyAudience) {
      XmoPrivacyAudience.contacts => StoryPrivacy.contacts,
      XmoPrivacyAudience.onlySelected => StoryPrivacy.custom,
      XmoPrivacyAudience.hideSelected => StoryPrivacy.contactsExcept,
    };

    final stories = await getMyStories();
    final updatedStories = stories.map((story) {
      return story.copyWith(
        privacy: privacy,
        customPrivacyList: settings.storyAudience == XmoPrivacyAudience.contacts
            ? const []
            : settings.storyUserIds,
      );
    }).toList();

    await _client.setAccountData(myUserId, storyAccountDataType, {
      'stories': updatedStories.map((story) => story.toJson()).toList(),
    });
    await _publishStorySnapshot(updatedStories);
  }

  // VIEW STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mark story as viewed
  /// Since we can't modify other users' account data, we'll track views locally
  Future<void> markStoryAsViewed(String storyOwnerId, String storyId) async {
    final myUserId = _client.userID;
    if (myUserId == null || myUserId.isEmpty || storyId.isEmpty) return;

    // Don't mark own stories as viewed
    if (storyOwnerId == myUserId) return;

    // Store viewed stories in our own account data.
    try {
      final viewedData = await _client.getAccountData(
        myUserId,
        viewedStoriesAccountDataKey,
      );

      final viewedStories = Map<String, List<dynamic>>.from(viewedData);
      final userViewedStories = List<String>.from(
        viewedStories[storyOwnerId] ?? [],
      );

      if (!userViewedStories.contains(storyId)) {
        userViewedStories.add(storyId);
        viewedStories[storyOwnerId] = userViewedStories;

        await _client.setAccountData(
          myUserId,
          viewedStoriesAccountDataKey,
          viewedStories,
        );

        debugPrint('[StoryService] Marked story $storyId as viewed');
      }
    } catch (e) {
      debugPrint('[StoryService] Failed to store local viewed state: $e');
    }

    final receiptKey = '$storyOwnerId::$storyId';
    if (!_pendingStoryViewReceipts.add(receiptKey)) return;

    try {
      final sentData = await _loadSentStoryViewReceipts(myUserId);
      final sentForOwner = List<String>.from(
        sentData[storyOwnerId] ?? const [],
      );
      if (sentForOwner.contains(storyId)) return;

      final directRoom = _client.rooms.firstWhere(
        (room) => room.isDirectChat && room.directChatMatrixID == storyOwnerId,
        orElse: () => throw Exception('No direct chat found'),
      );

      await directRoom.sendEvent({
        'msgtype': storyViewEventType,
        'story_id': storyId,
        'viewer_id': myUserId,
        'viewed_at': DateTime.now().millisecondsSinceEpoch,
      }, type: storyViewEventType);

      sentForOwner.add(storyId);
      if (sentForOwner.length > _maxStoredViewReceiptsPerOwner) {
        sentForOwner.removeRange(
          0,
          sentForOwner.length - _maxStoredViewReceiptsPerOwner,
        );
      }
      sentData[storyOwnerId] = sentForOwner;
      await _client.setAccountData(
        myUserId,
        _sentStoryViewReceiptsAccountDataKey,
        sentData,
      );
      debugPrint('[StoryService] Sent view receipt for story $storyId');
    } catch (e) {
      // Do not mark the receipt as sent. Opening the story again retries it.
      debugPrint('[StoryService] Failed to send view receipt: $e');
    } finally {
      _pendingStoryViewReceipts.remove(receiptKey);
    }
  }

  Future<Map<String, List<String>>> _loadSentStoryViewReceipts(
    String myUserId,
  ) async {
    try {
      final data = await _client.getAccountData(
        myUserId,
        _sentStoryViewReceiptsAccountDataKey,
      );
      return data.map(
        (ownerId, storyIds) => MapEntry(
          ownerId,
          storyIds is List ? storyIds.whereType<String>().toList() : <String>[],
        ),
      );
    } catch (_) {
      return <String, List<String>>{};
    }
  }

  /// Get list of users who viewed a story
  Future<List<StoryView>> getStoryViewers(String storyId) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return [];

      final viewers = <StoryView>[];
      final ownedStories = await getMyStories(includeRemoteViews: false);
      Story? matchingStory;
      for (final story in ownedStories) {
        if (story.id == storyId) {
          matchingStory = story;
          break;
        }
      }
      final historyCutoff =
          (matchingStory?.createdAt ?? DateTime.now().subtract(_storyDuration))
              .subtract(_storyViewHistoryGrace);

      // Get all direct chat rooms
      final directRooms = _client.rooms.where((r) => r.isDirectChat);

      // Look for view receipt events in each room
      for (final room in directRooms) {
        try {
          final timeline = await room.getTimeline();
          await _loadStoryViewHistory(timeline, historyCutoff);

          // Search for view receipt events for this story
          for (final event in timeline.events) {
            if (event.type != storyViewEventType) continue;
            final receipt = parseStoryViewReceipt(
              content: event.content,
              senderId: event.senderId,
              receivedAt: event.originServerTs,
            );
            if (receipt == null ||
                receipt.storyId != storyId ||
                receipt.viewerId == myUserId) {
              continue;
            }

            var viewerName = _storyViewerFallbackName(receipt.viewerId);
            try {
              final profile = await _client.getProfileFromUserId(
                receipt.viewerId,
              );
              final displayName = profile.displayName?.trim();
              if (displayName != null && displayName.isNotEmpty) {
                viewerName = displayName;
              }
            } catch (e) {
              debugPrint('[StoryService] Failed to get viewer profile: $e');
            }

            viewers.add(
              StoryView(
                storyId: storyId,
                viewerId: receipt.viewerId,
                viewerName: viewerName,
                viewedAt: receipt.viewedAt,
              ),
            );
          }
        } catch (e) {
          debugPrint('[StoryService] Failed to check room ${room.id}: $e');
        }
      }

      // Remove duplicates and sort by view time
      final uniqueViewers = <String, StoryView>{};
      for (final viewer in viewers) {
        if (!uniqueViewers.containsKey(viewer.viewerId) ||
            viewer.viewedAt.isAfter(uniqueViewers[viewer.viewerId]!.viewedAt)) {
          uniqueViewers[viewer.viewerId] = viewer;
        }
      }

      final result = uniqueViewers.values.toList()
        ..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));

      return result;
    } catch (e) {
      debugPrint('[StoryService] Failed to get story viewers: $e');
      return [];
    }
  }

  String _storyViewerFallbackName(String userId) {
    final value = userId.startsWith('@') ? userId.substring(1) : userId;
    final separator = value.indexOf(':');
    final localpart = separator == -1 ? value : value.substring(0, separator);
    return localpart.isEmpty ? userId : localpart;
  }

  Future<void> _loadStoryViewHistory(Timeline timeline, DateTime cutoff) async {
    for (var page = 0; page < _storyViewHistoryMaxPages; page++) {
      if (timeline.events.isNotEmpty &&
          !timeline.events.last.originServerTs.isAfter(cutoff)) {
        return;
      }
      if (!timeline.canRequestHistory) return;

      final previousLength = timeline.events.length;
      await timeline.requestHistory(historyCount: _storyViewHistoryPageSize);
      if (timeline.events.length == previousLength) return;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DELETE STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Delete a story
  Future<void> deleteStory(String storyId) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return;

      // Get existing stories
      final existingStories = await getMyStories();

      // Remove the story
      final updatedStories = existingStories
          .where((s) => s.id != storyId)
          .toList();

      // Save updated stories to account data
      final storiesJson = updatedStories.map((s) => s.toJson()).toList();
      await _client.setAccountData(myUserId, storyAccountDataType, {
        'stories': storiesJson,
      });

      // Broadcast updated list to contacts
      await _publishStorySnapshot(updatedStories);

      debugPrint('[StoryService] Deleted story: $storyId');
    } catch (e) {
      debugPrint('[StoryService] Failed to delete story: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clean up expired stories (should be called periodically)
  Future<void> cleanupExpiredStories() async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return;

      final existingStories = await getMyStories();
      final activeStories = existingStories.where((s) => !s.isExpired).toList();

      // Only update if there are expired stories
      if (activeStories.length < existingStories.length) {
        final storiesJson = activeStories.map((s) => s.toJson()).toList();
        await _client.setAccountData(myUserId, storyAccountDataType, {
          'stories': storiesJson,
        });

        // Broadcast updated list to contacts
        await _publishStorySnapshot(activeStories);

        debugPrint(
          '[StoryService] Cleaned up ${existingStories.length - activeStories.length} expired stories',
        );
      }
    } catch (e) {
      debugPrint('[StoryService] Failed to cleanup expired stories: $e');
    }
  }

  Future<Profile?> _getProfileSafely(String userId) async {
    try {
      return await _client.getProfileFromUserId(userId);
    } catch (e) {
      debugPrint('[StoryService] Failed to get profile for $userId: $e');
      return null;
    }
  }

  Future<List<Story>> _applyOwnProfileToStories(List<Story> stories) async {
    final myUserId = _client.userID;
    if (myUserId == null || stories.isEmpty) return stories;

    final profile = await _getProfileSafely(myUserId);
    if (profile == null) return stories;

    final displayName = MatrixIdentity.displayName(
      userId: myUserId,
      candidate: profile.displayName,
    );
    final avatarUrl = profile.avatarUrl?.toString();
    return stories.map((story) {
      if (story.userId != myUserId) return story;
      return story.copyWith(
        userName: displayName,
        userAvatarUrl: avatarUrl ?? story.userAvatarUrl,
      );
    }).toList();
  }

  bool isDirectChatRoom(String roomId) {
    return _client.rooms.any((room) => room.id == roomId && room.isDirectChat);
  }

  Future<List<String>> getViewedStoryIds(String storyOwnerId) async {
    final myUserId = _client.userID;
    if (myUserId == null || myUserId == storyOwnerId) return const [];

    try {
      final viewedData = await _client.getAccountData(
        myUserId,
        viewedStoriesAccountDataKey,
      );
      final viewedStories = Map<String, dynamic>.from(viewedData);
      return List<String>.from(viewedStories[storyOwnerId] ?? const []);
    } catch (e) {
      debugPrint(
        '[StoryService] Failed to get viewed story IDs for $storyOwnerId: $e',
      );
      return const [];
    }
  }

  Future<UserStories?> buildUserStoriesFromUpdateContent(
    Map<String, dynamic> eventJson,
  ) async {
    try {
      if (eventJson['type'] != storyUpdateEventType) return null;

      final rawContent = eventJson['content'];
      if (rawContent is! Map) return null;
      final content = Map<String, dynamic>.from(rawContent);

      final userId = _safeString(content['user_id'], Story.maxUserIdLength);
      final senderId = _safeString(eventJson['sender'], Story.maxUserIdLength);
      final myUserId = _client.userID;
      if (userId == null ||
          senderId == null ||
          senderId != userId ||
          userId == myUserId) {
        return null;
      }

      final stories = await _applyViewedOverlay(
        userId,
        _parseStoryList(
          content['stories'],
          expectedOwnerId: userId,
        ).where((story) => !story.isExpired).toList(),
      );

      String userName = MatrixIdentity.displayName(
        userId: userId,
        candidate: stories.isNotEmpty ? stories.first.userName : null,
      );
      String? avatarUrl = stories.isNotEmpty
          ? stories.first.userAvatarUrl
          : null;

      final profile = await _getProfileSafely(userId);
      if (profile != null) {
        userName = MatrixIdentity.displayName(
          userId: userId,
          candidate: profile.displayName ?? userName,
        );
        avatarUrl = profile.avatarUrl?.toString() ?? avatarUrl;
      }

      return UserStories(
        userId: userId,
        userName: userName,
        userAvatarUrl: avatarUrl,
        stories: stories,
        snapshotUpdatedAt: _storySnapshotTimestamp(eventJson),
      );
    } catch (e) {
      debugPrint('[StoryService] Failed to build stories from update: $e');
      return null;
    }
  }

  int _storyEventVersion(Event event) {
    return _millisecondsValue(event.content['updated_at']) ??
        event.originServerTs.millisecondsSinceEpoch;
  }

  DateTime? _storySnapshotTimestamp(Map<String, dynamic> eventJson) {
    final rawContent = eventJson['content'];
    final content = rawContent is Map
        ? rawContent.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    return _dateTimeFromMilliseconds(
      content['updated_at'] ?? eventJson['origin_server_ts'],
    );
  }

  DateTime? _dateTimeFromMilliseconds(Object? value) {
    final milliseconds = _millisecondsValue(value);
    if (milliseconds == null || milliseconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  int? _millisecondsValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<List<Story>> _applyViewedOverlay(
    String storyOwnerId,
    List<Story> stories,
  ) async {
    final myUserId = _client.userID;
    if (myUserId == null || myUserId == storyOwnerId || stories.isEmpty) {
      return stories;
    }

    final viewedStoryIds = (await getViewedStoryIds(storyOwnerId)).toSet();
    if (viewedStoryIds.isEmpty) return stories;

    return stories.map((story) {
      if (!viewedStoryIds.contains(story.id) ||
          story.viewedBy.contains(myUserId)) {
        return story;
      }
      return story.copyWith(viewedBy: [...story.viewedBy, myUserId]);
    }).toList();
  }

  Future<List<Story>> _applyRemoteViewsToOwnedStories(
    List<Story> stories,
  ) async {
    final myUserId = _client.userID;
    if (myUserId == null || stories.isEmpty) return stories;

    final storyIds = stories.map((story) => story.id).toSet();
    final viewersByStory = <String, Set<String>>{};
    final historyCutoff = stories
        .map((story) => story.createdAt)
        .reduce((earliest, next) => next.isBefore(earliest) ? next : earliest)
        .subtract(_storyViewHistoryGrace);

    for (final room in _client.rooms.where((room) => room.isDirectChat)) {
      try {
        final timeline = await room.getTimeline();
        await _loadStoryViewHistory(timeline, historyCutoff);
        for (final event in timeline.events) {
          if (event.type != storyViewEventType) continue;

          final receipt = parseStoryViewReceipt(
            content: event.content,
            senderId: event.senderId,
            receivedAt: event.originServerTs,
          );
          if (receipt == null ||
              !storyIds.contains(receipt.storyId) ||
              receipt.viewerId == myUserId) {
            continue;
          }

          viewersByStory
              .putIfAbsent(receipt.storyId, () => <String>{})
              .add(receipt.viewerId);
        }
      } catch (e) {
        debugPrint(
          '[StoryService] Failed to apply remote views in ${room.id}: $e',
        );
      }
    }

    if (viewersByStory.isEmpty) return stories;

    return stories.map((story) {
      final viewers = viewersByStory[story.id];
      if (viewers == null || viewers.isEmpty) {
        return story;
      }
      return story.copyWith(viewedBy: {...story.viewedBy, ...viewers}.toList());
    }).toList();
  }

  List<Story> _parseStoryList(Object? value, {String? expectedOwnerId}) {
    if (value is! List || value.length > _maxStoriesPerSnapshot) {
      return const [];
    }

    final stories = <Story>[];
    final seenIds = <String>{};
    for (final item in value) {
      if (item is! Map) continue;
      final story = Story.tryFromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (story == null ||
          (expectedOwnerId != null && story.userId != expectedOwnerId) ||
          !seenIds.add(story.id)) {
        continue;
      }
      stories.add(
        story.copyWith(
          userName: MatrixIdentity.displayName(
            userId: story.userId,
            candidate: story.userName,
          ),
        ),
      );
    }
    return stories;
  }

  void _validateCreateRequest(CreateStoryRequest request) {
    final clientRequestId = request.clientRequestId?.trim();
    if (clientRequestId != null &&
        (clientRequestId.isEmpty ||
            clientRequestId.length > Story.maxIdLength ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(clientRequestId))) {
      throw const StoryValidationException('Invalid Story publish identifier');
    }

    final caption = request.caption;
    if (caption != null && caption.length > Story.maxCaptionLength) {
      throw const StoryValidationException('Story caption is too long');
    }

    final customAudience = request.customPrivacyList;
    if (customAudience != null &&
        customAudience.length > Story.maxAudienceEntries) {
      throw const StoryValidationException('Story audience is too large');
    }

    final mediaBytes = request.mediaBytes;
    final mediaFilePath = request.mediaFilePath?.trim();
    if (mediaBytes != null &&
        mediaBytes.isNotEmpty &&
        mediaFilePath != null &&
        mediaFilePath.isNotEmpty) {
      throw const StoryValidationException(
        'Story media must use either bytes or a file, not both',
      );
    }
    switch (request.mediaType) {
      case StoryMediaType.text:
        final text = request.textContent?.trim() ?? '';
        if (text.isEmpty) {
          throw const StoryValidationException('Story text is required');
        }
        if (text.length > Story.maxTextLength) {
          throw const StoryValidationException('Story text is too long');
        }
        if (request.hasMedia) {
          throw const StoryValidationException(
            'Text stories cannot contain media',
          );
        }
        break;
      case StoryMediaType.image:
        _validateMediaSource(request, _maxImageBytes, 'image');
        _validateMimeType(request.mediaMimeType, prefix: 'image/');
        break;
      case StoryMediaType.video:
        _validateMediaSource(request, _maxVideoBytes, 'video');
        _validateMimeType(request.mediaMimeType, prefix: 'video/');
        break;
    }

    final thumbnail = request.thumbnailBytes;
    if (thumbnail != null && thumbnail.length > _maxThumbnailBytes) {
      throw const StoryValidationException('Story thumbnail is too large');
    }
  }

  void _validateMediaSource(
    CreateStoryRequest request,
    int maximumBytes,
    String label,
  ) {
    final mediaFilePath = request.mediaFilePath?.trim();
    if (mediaFilePath != null && mediaFilePath.isNotEmpty) {
      final file = File(mediaFilePath);
      if (!file.existsSync()) {
        throw StoryValidationException('Story $label is no longer available');
      }
      final length = file.lengthSync();
      if (length <= 0) {
        throw StoryValidationException('Story $label is empty');
      }
      final reportedLength = request.mediaSizeBytes;
      if (reportedLength != null && reportedLength != length) {
        throw StoryValidationException('Story $label changed before upload');
      }
      if (length > maximumBytes) {
        throw StoryValidationException('Story $label is too large');
      }
      return;
    }
    _validateMediaBytes(
      request.mediaBytes,
      maximumBytes: maximumBytes,
      label: label,
    );
  }

  void _validateMediaBytes(
    Uint8List? bytes, {
    required int maximumBytes,
    required String label,
  }) {
    if (bytes == null || bytes.isEmpty) {
      throw StoryValidationException('Story $label is required');
    }
    if (bytes.length > maximumBytes) {
      throw StoryValidationException('Story $label is too large');
    }
  }

  void _validateMimeType(String? value, {required String prefix}) {
    if (value == null || value.isEmpty) return;
    final normalized = value.toLowerCase().split(';').first.trim();
    if (!normalized.startsWith(prefix) ||
        normalized.length > Story.maxMimeTypeLength) {
      throw const StoryValidationException('Unsupported story media type');
    }
  }

  String? _safeString(Object? value, int maximumLength) {
    if (value is! String) return null;
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > maximumLength) return null;
    return normalized;
  }

  String? _safeOptionalString(Object? value, int maximumLength) {
    if (value == null) return null;
    return _safeString(value, maximumLength);
  }
}

class StoryValidationException implements Exception {
  final String message;

  const StoryValidationException(this.message);

  @override
  String toString() => message;
}

class StoryUploadException implements Exception {
  final Object? cause;

  const StoryUploadException(this.cause);

  @override
  String toString() => 'Story upload failed. Check your connection and retry.';
}
