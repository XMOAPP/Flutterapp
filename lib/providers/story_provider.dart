import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import '../models/story_models.dart';
import '../services/story_service.dart';

/// Provider for managing Stories state
class StoryProvider extends ChangeNotifier {
  final StoryService _storyService;

  StoryProvider(this._storyService) {
    _init();
  }

  // State
  List<Story> _myStories = [];
  List<UserStories> _contactStories = [];
  bool _loading = false;
  String? _error;
  Timer? _refreshTimer;
  Timer? _cleanupTimer;
  StreamSubscription<EventUpdate>? _eventSub;
  StreamSubscription<BasicEvent>? _accountDataSub;
  bool _hasLoadedContactTimeline = false;

  // Getters
  List<Story> get myStories => _myStories;
  List<UserStories> get contactStories => _contactStories;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasMyStories => _myStories.where((s) => !s.isExpired).isNotEmpty;

  /// Initialize provider
  void _init() {
    _eventSub = _storyService.onEvent.listen(_handleEventUpdate);
    _accountDataSub = _storyService.onAccountData.listen((event) {
      if (event.type == StoryService.storyAccountDataType) {
        unawaited(loadMyStories());
      }
    });

    // Matrix timeline scans are expensive. New story/view events update this
    // provider directly, so periodic work refreshes only account data.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_storyService.retryPendingStoryDistribution());
      refreshStories(forceTimelineScan: false);
    });

    // Cleanup expired stories every 5 minutes
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _storyService.cleanupExpiredStories();
    });

    // Initial load
    unawaited(_storyService.retryPendingStoryDistribution());
    refreshStories();
  }

  Future<void> _handleEventUpdate(EventUpdate update) async {
    try {
      if (update.type != EventUpdateType.timeline ||
          !_storyService.isDirectChatRoom(update.roomID)) {
        return;
      }

      final eventType = update.content['type'] as String?;
      if (eventType == StoryService.storyUpdateEventType) {
        await _handleStoryUpdate(update.content);
      } else if (eventType == StoryService.storyViewEventType) {
        _handleStoryView(update.content);
      }
    } catch (e) {
      debugPrint('[StoryProvider] Failed to handle story event: $e');
    }
  }

  Future<void> _handleStoryUpdate(Map<String, dynamic> eventJson) async {
    final userStories = await _storyService.buildUserStoriesFromUpdateContent(
      eventJson,
    );
    if (userStories == null) return;

    if (!_upsertContactStories(userStories)) return;
    unawaited(_storyService.cacheContactStories(_contactStories));
    notifyListeners();
  }

  void _handleStoryView(Map<String, dynamic> eventJson) {
    final rawContent = eventJson['content'];
    if (rawContent is! Map) return;

    final content = Map<String, dynamic>.from(rawContent);
    final senderId = eventJson['sender'] as String?;
    final receivedAt = _eventTimestamp(eventJson['origin_server_ts']);
    if (senderId == null || receivedAt == null) return;

    final receipt = parseStoryViewReceipt(
      content: content,
      senderId: senderId,
      receivedAt: receivedAt,
    );
    final myUserId = _storyService.currentUserId;

    if (receipt == null || myUserId == null) return;
    if (receipt.viewerId == myUserId) return;

    final storyIndex =
        _myStories.indexWhere((story) => story.id == receipt.storyId);
    if (storyIndex == -1) return;

    final story = _myStories[storyIndex];
    if (story.viewedBy.contains(receipt.viewerId)) return;

    final updatedStories = List<Story>.from(_myStories);
    updatedStories[storyIndex] = story.copyWith(
      viewedBy: [...story.viewedBy, receipt.viewerId],
    );
    _myStories = updatedStories;
    notifyListeners();
  }

  DateTime? _eventTimestamp(Object? value) {
    final milliseconds = switch (value) {
      int number => number,
      num number => number.toInt(),
      _ => int.tryParse(value?.toString() ?? ''),
    };
    if (milliseconds == null || milliseconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  bool _upsertContactStories(UserStories incoming) {
    final updatedStories = incoming.activeStories;
    final existingIndex = _contactStories.indexWhere(
      (stories) => stories.userId == incoming.userId,
    );
    if (existingIndex != -1 &&
        !shouldReplaceStorySnapshot(
          _contactStories[existingIndex],
          incoming,
        )) {
      return false;
    }

    if (existingIndex != -1) {
      _contactStories.removeAt(existingIndex);
    }

    if (updatedStories.isEmpty) {
      _sortContactStories();
      return true;
    }

    _contactStories.add(UserStories(
      userId: incoming.userId,
      userName: incoming.userName,
      userAvatarUrl: incoming.userAvatarUrl,
      stories: updatedStories,
      snapshotUpdatedAt: incoming.snapshotUpdatedAt,
    ));
    _sortContactStories();
    return true;
  }

  void _sortContactStories() {
    _contactStories.sort((a, b) {
      final aLatest = a.latestStory?.createdAt ?? DateTime(0);
      final bLatest = b.latestStory?.createdAt ?? DateTime(0);
      return bLatest.compareTo(aLatest);
    });
  }

  void _markStoryViewedLocally(String storyOwnerId, String storyId) {
    final myUserId = _storyService.currentUserId;
    if (myUserId == null) return;

    final userStoriesIndex = _contactStories.indexWhere(
      (stories) => stories.userId == storyOwnerId,
    );
    if (userStoriesIndex == -1) return;

    final userStories = _contactStories[userStoriesIndex];
    final updatedStories = userStories.stories.map((story) {
      if (story.id != storyId || story.viewedBy.contains(myUserId)) {
        return story;
      }
      return story.copyWith(viewedBy: [...story.viewedBy, myUserId]);
    }).toList();

    _contactStories[userStoriesIndex] = UserStories(
      userId: userStories.userId,
      userName: userStories.userName,
      userAvatarUrl: userStories.userAvatarUrl,
      stories: updatedStories,
      snapshotUpdatedAt: userStories.snapshotUpdatedAt,
    );
    unawaited(_storyService.cacheContactStories(_contactStories));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD STORIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Refresh all stories
  Future<void> refreshStories({bool forceTimelineScan = false}) async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      // Show persisted event IDs/story view state immediately. We only scan
      // every direct-room timeline for the first cache miss or an explicit
      // pull-to-refresh style request.
      if (_contactStories.isEmpty) {
        _contactStories = await _storyService.loadCachedContactStories();
      }

      _myStories = await _storyService.getMyStories(
        includeRemoteViews: forceTimelineScan || !_hasLoadedContactTimeline,
      );

      if (forceTimelineScan || !_hasLoadedContactTimeline) {
        _contactStories = await _storyService.getAllContactStories();
        _hasLoadedContactTimeline = true;
        await _storyService.cacheContactStories(_contactStories);
      }

      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      debugPrint('[StoryProvider] Failed to refresh stories: $e');
    }
  }

  /// Load my stories only
  Future<void> loadMyStories() async {
    try {
      _myStories = await _storyService.getMyStories(includeRemoteViews: false);
      notifyListeners();
    } catch (e) {
      debugPrint('[StoryProvider] Failed to load my stories: $e');
    }
  }

  /// Load contact stories only
  Future<void> loadContactStories() async {
    try {
      _contactStories = await _storyService.getAllContactStories();
      _hasLoadedContactTimeline = true;
      await _storyService.cacheContactStories(_contactStories);
      notifyListeners();
    } catch (e) {
      debugPrint('[StoryProvider] Failed to load contact stories: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CREATE STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new story
  Future<Story?> createStory(
    CreateStoryRequest request, {
    ValueChanged<StoryCreationProgress>? onProgress,
    StoryCreationCancellationToken? cancellationToken,
  }) async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      final story = await _storyService.createStory(
        request,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );

      // Add to my stories
      _myStories.add(story);

      _loading = false;
      notifyListeners();

      return story;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      debugPrint('[StoryProvider] Failed to create story: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VIEW STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mark story as viewed
  Future<void> markStoryAsViewed(String storyOwnerId, String storyId) async {
    try {
      await _storyService.markStoryAsViewed(storyOwnerId, storyId);

      _markStoryViewedLocally(storyOwnerId, storyId);
      notifyListeners();
    } catch (e) {
      debugPrint('[StoryProvider] Failed to mark story as viewed: $e');
    }
  }

  /// Get viewers for a story
  Future<List<StoryView>> getStoryViewers(String storyId) async {
    try {
      return await _storyService.getStoryViewers(storyId);
    } catch (e) {
      debugPrint('[StoryProvider] Failed to get story viewers: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DELETE STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Delete a story
  Future<bool> deleteStory(String storyId) async {
    try {
      await _storyService.deleteStory(storyId);

      // Remove from local state
      _myStories.removeWhere((s) => s.id == storyId);
      notifyListeners();

      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      debugPrint('[StoryProvider] Failed to delete story: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get active stories count
  int get activeStoriesCount {
    return _myStories.where((s) => !s.isExpired).length;
  }

  /// Get unviewed contact stories count
  int getUnviewedContactStoriesCount(String myUserId) {
    int count = 0;
    for (final userStories in _contactStories) {
      if (!userStories.allViewedBy(myUserId)) {
        count++;
      }
    }
    return count;
  }

  /// Check if user has unviewed stories
  bool hasUnviewedStories(String userId, String myUserId) {
    final userStories = _contactStories.firstWhere(
      (us) => us.userId == userId,
      orElse: () => UserStories(userId: userId, userName: '', stories: []),
    );
    return !userStories.allViewedBy(myUserId);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _accountDataSub?.cancel();
    _refreshTimer?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }
}
