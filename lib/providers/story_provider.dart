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

  // Getters
  List<Story> get myStories => _myStories;
  List<UserStories> get contactStories => _contactStories;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasMyStories => _myStories.where((s) => !s.isExpired).isNotEmpty;

  /// Initialize provider
  void _init() {
    _eventSub = _storyService.onEvent.listen(_handleEventUpdate);

    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshStories();
    });

    // Cleanup expired stories every 5 minutes
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _storyService.cleanupExpiredStories();
    });

    // Initial load
    refreshStories();
  }

  Future<void> _handleEventUpdate(EventUpdate update) async {
    try {
      if (update.type == EventUpdateType.accountData &&
          update.content['type'] == StoryService.storyAccountDataType) {
        await loadMyStories();
        return;
      }

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

    _upsertContactStories(userStories);
    notifyListeners();
  }

  void _handleStoryView(Map<String, dynamic> eventJson) {
    final rawContent = eventJson['content'];
    if (rawContent is! Map) return;

    final content = Map<String, dynamic>.from(rawContent);
    final storyId = content['story_id'] as String?;
    final viewerId = content['viewer_id'] as String?;
    final myUserId = _storyService.currentUserId;

    if (storyId == null || viewerId == null || myUserId == null) return;
    if (viewerId == myUserId) return;

    final storyIndex = _myStories.indexWhere((story) => story.id == storyId);
    if (storyIndex == -1) return;

    final story = _myStories[storyIndex];
    if (story.viewedBy.contains(viewerId)) return;

    final updatedStories = List<Story>.from(_myStories);
    updatedStories[storyIndex] = story.copyWith(
      viewedBy: [...story.viewedBy, viewerId],
    );
    _myStories = updatedStories;
    notifyListeners();
  }

  void _upsertContactStories(UserStories incoming) {
    final updatedStories = incoming.activeStories;
    _contactStories.removeWhere((stories) => stories.userId == incoming.userId);

    if (updatedStories.isEmpty) {
      _sortContactStories();
      return;
    }

    _contactStories.add(UserStories(
      userId: incoming.userId,
      userName: incoming.userName,
      userAvatarUrl: incoming.userAvatarUrl,
      stories: updatedStories,
    ));
    _sortContactStories();
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD STORIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Refresh all stories
  Future<void> refreshStories() async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      // Load my stories and contact stories in parallel
      final results = await Future.wait([
        _storyService.getMyStories(),
        _storyService.getAllContactStories(),
      ]);

      _myStories = results[0] as List<Story>;
      _contactStories = results[1] as List<UserStories>;

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
      _myStories = await _storyService.getMyStories();
      notifyListeners();
    } catch (e) {
      debugPrint('[StoryProvider] Failed to load my stories: $e');
    }
  }

  /// Load contact stories only
  Future<void> loadContactStories() async {
    try {
      _contactStories = await _storyService.getAllContactStories();
      notifyListeners();
    } catch (e) {
      debugPrint('[StoryProvider] Failed to load contact stories: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CREATE STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new story
  Future<Story?> createStory(CreateStoryRequest request) async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      final story = await _storyService.createStory(request);

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
    _refreshTimer?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }
}
