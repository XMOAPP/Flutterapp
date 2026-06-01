import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import '../models/story_models.dart';
import 'matrix_service.dart';
import 'privacy_service.dart';

/// Service for managing Stories feature
class StoryService {
  final MatrixService _matrixService;

  StoryService(this._matrixService);

  Client get _client => _matrixService.client;
  Stream<EventUpdate> get onEvent => _matrixService.onEvent;
  String? get currentUserId => _client.userID;

  // Custom event type for stories
  static const String storyAccountDataType = 'xmo.user.stories';
  static const String storyUpdateEventType = 'xmo.story.update';
  static const String storyViewEventType = 'xmo.story.view';
  static const String viewedStoriesAccountDataKey = 'xmo.user.viewed_stories';
  static const Duration _storyDuration = Duration(hours: 24);

  // ═══════════════════════════════════════════════════════════════════════════
  // CREATE STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Creates a new story
  Future<Story> createStory(CreateStoryRequest request) async {
    final myUserId = _client.userID;
    if (myUserId == null) throw Exception('User not logged in');

    String? mediaUrl;
    String? thumbnailUrl;
    final profile = await _getProfileSafely(myUserId);

    // Upload media if provided
    if (request.mediaBytes != null) {
      mediaUrl = await _uploadStoryMedia(
        request.mediaBytes!,
        filename: request.mediaFileName,
        contentType: request.mediaMimeType,
      );
    }

    if (request.thumbnailBytes != null && request.thumbnailBytes!.isNotEmpty) {
      thumbnailUrl = await _uploadStoryMedia(
        request.thumbnailBytes!,
        filename: 'story_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: 'image/jpeg',
      );
    }

    // Create story object
    final now = DateTime.now();
    final story = Story(
      id: _generateStoryId(),
      userId: myUserId,
      userName: profile?.displayName ?? myUserId,
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
    await _saveStoryToAccountData(story);

    debugPrint('[StoryService] Created story: ${story.id}');
    return story;
  }

  /// Upload story media to Matrix media repository
  Future<String> _uploadStoryMedia(
    Uint8List bytes, {
    String? filename,
    String? contentType,
  }) async {
    try {
      final uri = await _client.uploadContent(
        bytes,
        filename: filename ?? 'story_${DateTime.now().millisecondsSinceEpoch}',
        contentType: contentType,
      );
      return uri.toString();
    } catch (e) {
      debugPrint('[StoryService] Failed to upload media: $e');
      rethrow;
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

      // Add new story
      existingStories.add(story);

      // Remove expired stories
      final activeStories = existingStories.where((s) => !s.isExpired).toList();

      // Save to account data (for our own reference)
      final storiesJson = activeStories.map((s) => s.toJson()).toList();
      await _client.setAccountData(
        myUserId,
        storyAccountDataType,
        {'stories': storiesJson},
      );

      // Broadcast to all allowed direct chat rooms so contacts can see our stories
      await _broadcastStoriesToContacts(activeStories);
    } catch (e) {
      debugPrint('[StoryService] Failed to save story: $e');
      rethrow;
    }
  }

  /// Broadcast stories to all direct chat rooms
  /// Uses regular events instead of state events for better compatibility
  Future<void> _broadcastStoriesToContacts(List<Story> stories) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return;

      // Get all direct chat rooms
      final directRooms = _client.rooms.where((r) => r.isDirectChat);

      // Send event to each direct chat room
      for (final room in directRooms) {
        try {
          final viewerId =
              _matrixService.getDirectPeerUserId(room) ?? room.directChatMatrixID;
          if (viewerId == null || viewerId == myUserId) continue;

          final visibleStories = stories
              .where((story) => _canUserViewStory(story, viewerId))
              .toList();
          final storiesJson = visibleStories.map((s) => s.toJson()).toList();

          await room.sendEvent({
            'msgtype': storyUpdateEventType,
            'user_id': myUserId,
            'stories': storiesJson,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          }, type: storyUpdateEventType);
          debugPrint('[StoryService] Broadcasted stories to room ${room.id}');
        } catch (e) {
          debugPrint(
              '[StoryService] Failed to broadcast to room ${room.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('[StoryService] Failed to broadcast stories: $e');
    }
  }

  bool _canUserViewStory(Story story, String userId) {
    switch (story.privacy) {
      case StoryPrivacy.contacts:
      case StoryPrivacy.allUsers:
        return true;
      case StoryPrivacy.custom:
        return story.customPrivacyList?.contains(userId) ?? false;
      case StoryPrivacy.contactsExcept:
        return !(story.customPrivacyList?.contains(userId) ?? false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GET STORIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get my stories
  Future<List<Story>> getMyStories() async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return [];

      final accountData =
          await _client.getAccountData(myUserId, storyAccountDataType);

      final storiesJson = accountData['stories'] as List<dynamic>?;
      if (storiesJson == null) return [];

      final stories = storiesJson
          .map((json) => Story.fromJson(json as Map<String, dynamic>))
          .where((s) => !s.isExpired) // Filter expired
          .toList();

      final enrichedStories = await _applyOwnProfileToStories(stories);
      return await _applyRemoteViewsToOwnedStories(enrichedStories);
    } catch (e) {
      debugPrint('[StoryService] Failed to get my stories: $e');
      return [];
    }
  }

  /// Get stories from a specific user
  /// Stories are broadcasted as timeline events in direct chat rooms
  Future<List<Story>> getUserStories(String userId) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return [];

      // If it's our own stories, read from account data
      if (userId == myUserId) {
        return await getMyStories();
      }

      // For other users, find the direct chat room and look for story update events
      final directRoom = _client.rooms.firstWhere(
        (r) => r.isDirectChat && r.directChatMatrixID == userId,
        orElse: () => throw Exception('No direct chat found'),
      );

      // Get timeline and look for the latest story update event from this user
      final timeline = await directRoom.getTimeline();

      // Find the most recent story update event from this user
      Event? latestStoryEvent;
      for (final event in timeline.events.reversed) {
        if (event.type == storyUpdateEventType &&
            event.content['user_id'] == userId) {
          latestStoryEvent = event;
          break;
        }
      }

      if (latestStoryEvent == null) return [];

      final userStories = await buildUserStoriesFromUpdateContent({
        'type': latestStoryEvent.type,
        'content': latestStoryEvent.content,
      });

      return userStories?.stories ?? [];
    } catch (e) {
      debugPrint('[StoryService] Failed to get user stories for $userId: $e');
      return [];
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
          final stories = await getUserStories(userId);
          if (stories.isNotEmpty) {
            final user = await _client.getProfileFromUserId(userId);
            allUserStories.add(UserStories(
              userId: userId,
              userName: user.displayName ?? userId,
              userAvatarUrl: user.avatarUrl?.toString(),
              stories: stories,
            ));
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
        customPrivacyList:
            settings.storyAudience == XmoPrivacyAudience.contacts
                ? const []
                : settings.storyUserIds,
      );
    }).toList();

    await _client.setAccountData(
      myUserId,
      storyAccountDataType,
      {'stories': updatedStories.map((story) => story.toJson()).toList()},
    );
    await _broadcastStoriesToContacts(updatedStories);
  }

  // VIEW STORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mark story as viewed
  /// Since we can't modify other users' account data, we'll track views locally
  Future<void> markStoryAsViewed(String storyOwnerId, String storyId) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null || myUserId.isEmpty) return;

      // Don't mark own stories as viewed
      if (storyOwnerId == myUserId) return;

      // Store viewed stories in our own account data
      const viewedStoriesKey = 'xmo.user.viewed_stories';
      final viewedData =
          await _client.getAccountData(myUserId, viewedStoriesKey);

      final viewedStories = Map<String, List<dynamic>>.from(viewedData);
      final userViewedStories =
          List<String>.from(viewedStories[storyOwnerId] ?? []);

      if (!userViewedStories.contains(storyId)) {
        userViewedStories.add(storyId);
        viewedStories[storyOwnerId] = userViewedStories;

        await _client.setAccountData(
          myUserId,
          viewedStoriesKey,
          viewedStories,
        );

        debugPrint('[StoryService] Marked story $storyId as viewed');
      }

      // Also send a view receipt to the story owner via the direct chat room
      try {
        final directRoom = _client.rooms.firstWhere(
          (r) => r.isDirectChat && r.directChatMatrixID == storyOwnerId,
          orElse: () => throw Exception('No direct chat found'),
        );

        // Send a custom event to notify the story owner
        await directRoom.sendEvent({
          'msgtype': storyViewEventType,
          'story_id': storyId,
          'viewer_id': myUserId,
          'viewed_at': DateTime.now().millisecondsSinceEpoch,
        }, type: storyViewEventType);

        debugPrint('[StoryService] Sent view receipt for story $storyId');
      } catch (e) {
        debugPrint('[StoryService] Failed to send view receipt: $e');
      }
    } catch (e) {
      debugPrint('[StoryService] Failed to mark story as viewed: $e');
    }
  }

  /// Get list of users who viewed a story
  Future<List<StoryView>> getStoryViewers(String storyId) async {
    try {
      final myUserId = _client.userID;
      if (myUserId == null) return [];

      final viewers = <StoryView>[];

      // Get all direct chat rooms
      final directRooms = _client.rooms.where((r) => r.isDirectChat);

      // Look for view receipt events in each room
      for (final room in directRooms) {
        try {
          final timeline = await room.getTimeline();

          // Search for view receipt events for this story
          for (final event in timeline.events) {
            if (event.type == storyViewEventType &&
                event.content['story_id'] == storyId) {
              final viewerId = event.content['viewer_id'] as String?;
              final viewedAt = event.content['viewed_at'] as int?;

              if (viewerId != null && viewedAt != null) {
                try {
                  final profile = await _client.getProfileFromUserId(viewerId);
                  viewers.add(StoryView(
                    storyId: storyId,
                    viewerId: viewerId,
                    viewerName: profile.displayName ?? viewerId,
                    viewedAt: DateTime.fromMillisecondsSinceEpoch(viewedAt),
                  ));
                } catch (e) {
                  debugPrint('[StoryService] Failed to get viewer profile: $e');
                }
              }
            }
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
      final updatedStories =
          existingStories.where((s) => s.id != storyId).toList();

      // Save updated stories to account data
      final storiesJson = updatedStories.map((s) => s.toJson()).toList();
      await _client.setAccountData(
        myUserId,
        storyAccountDataType,
        {'stories': storiesJson},
      );

      // Broadcast updated list to contacts
      await _broadcastStoriesToContacts(updatedStories);

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
        await _client.setAccountData(
          myUserId,
          storyAccountDataType,
          {'stories': storiesJson},
        );

        // Broadcast updated list to contacts
        await _broadcastStoriesToContacts(activeStories);

        debugPrint(
            '[StoryService] Cleaned up ${existingStories.length - activeStories.length} expired stories');
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

    final displayName = profile.displayName;
    final avatarUrl = profile.avatarUrl?.toString();
    return stories.map((story) {
      if (story.userId != myUserId) return story;
      return story.copyWith(
        userName: displayName ?? story.userName,
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

      final userId = content['user_id'] as String?;
      final storiesJson = content['stories'] as List<dynamic>?;
      final myUserId = _client.userID;
      if (userId == null || userId == myUserId || storiesJson == null) {
        return null;
      }

      final stories = await _applyViewedOverlay(
        userId,
        storiesJson
            .map((json) => Story.fromJson(json as Map<String, dynamic>))
            .where((story) => !story.isExpired)
            .toList(),
      );

      String userName = stories.isNotEmpty ? stories.first.userName : userId;
      String? avatarUrl =
          stories.isNotEmpty ? stories.first.userAvatarUrl : null;

      final profile = await _getProfileSafely(userId);
      if (profile != null) {
        userName = profile.displayName ?? userName;
        avatarUrl = profile.avatarUrl?.toString() ?? avatarUrl;
      }

      return UserStories(
        userId: userId,
        userName: userName,
        userAvatarUrl: avatarUrl,
        stories: stories,
      );
    } catch (e) {
      debugPrint('[StoryService] Failed to build stories from update: $e');
      return null;
    }
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
      return story.copyWith(
        viewedBy: [...story.viewedBy, myUserId],
      );
    }).toList();
  }

  Future<List<Story>> _applyRemoteViewsToOwnedStories(
      List<Story> stories) async {
    final myUserId = _client.userID;
    if (myUserId == null || stories.isEmpty) return stories;

    final storyIds = stories.map((story) => story.id).toSet();
    final viewersByStory = <String, Set<String>>{};

    for (final room in _client.rooms.where((room) => room.isDirectChat)) {
      try {
        final timeline = await room.getTimeline();
        for (final event in timeline.events) {
          if (event.type != storyViewEventType) continue;

          final storyId = event.content['story_id'] as String?;
          final viewerId = event.content['viewer_id'] as String?;
          if (storyId == null ||
              viewerId == null ||
              !storyIds.contains(storyId) ||
              viewerId == myUserId) {
            continue;
          }

          viewersByStory.putIfAbsent(storyId, () => <String>{}).add(viewerId);
        }
      } catch (e) {
        debugPrint(
            '[StoryService] Failed to apply remote views in ${room.id}: $e');
      }
    }

    if (viewersByStory.isEmpty) return stories;

    return stories.map((story) {
      final viewers = viewersByStory[story.id];
      if (viewers == null || viewers.isEmpty) {
        return story;
      }
      return story.copyWith(
        viewedBy: {...story.viewedBy, ...viewers}.toList(),
      );
    }).toList();
  }
}
