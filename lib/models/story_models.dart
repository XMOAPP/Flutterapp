import 'package:flutter/foundation.dart';

/// Story media type
enum StoryMediaType {
  image,
  video,
  text,
}

/// Story privacy setting
enum StoryPrivacy {
  contacts, // Only direct chat contacts
  allUsers, // All users in shared rooms
  custom, // Custom list
}

/// Individual Story Item
class Story {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String? mediaUrl; // MXC URL for image/video
  final String? mediaMimeType;
  final String? thumbnailUrl; // MXC URL for video thumbnail
  final StoryMediaType mediaType;
  final String? caption;
  final String? textContent; // For text-only stories
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewedBy; // User IDs who viewed
  final StoryPrivacy privacy;
  final List<String>? customPrivacyList; // For custom privacy

  Story({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    this.mediaUrl,
    this.mediaMimeType,
    this.thumbnailUrl,
    required this.mediaType,
    this.caption,
    this.textContent,
    required this.createdAt,
    required this.expiresAt,
    this.viewedBy = const [],
    this.privacy = StoryPrivacy.contacts,
    this.customPrivacyList,
  });

  /// Check if story is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Check if story is viewed by specific user
  bool isViewedBy(String userId) => viewedBy.contains(userId);

  /// Get view count
  int get viewCount => viewedBy.length;

  /// Time remaining until expiry
  Duration get timeRemaining => expiresAt.difference(DateTime.now());

  /// Convert to JSON for Matrix state event
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'user_avatar_url': userAvatarUrl,
      'media_url': mediaUrl,
      'media_mime_type': mediaMimeType,
      'thumbnail_url': thumbnailUrl,
      'media_type': mediaType.name,
      'caption': caption,
      'text_content': textContent,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expires_at': expiresAt.millisecondsSinceEpoch,
      'viewed_by': viewedBy,
      'privacy': privacy.name,
      'custom_privacy_list': customPrivacyList,
    };
  }

  /// Create from JSON (Matrix state event)
  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String,
      userAvatarUrl: json['user_avatar_url'] as String?,
      mediaUrl: json['media_url'] as String?,
      mediaMimeType: json['media_mime_type'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      mediaType: StoryMediaType.values.firstWhere(
        (e) => e.name == json['media_type'],
        orElse: () => StoryMediaType.image,
      ),
      caption: json['caption'] as String?,
      textContent: json['text_content'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expires_at'] as int),
      viewedBy: (json['viewed_by'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      privacy: StoryPrivacy.values.firstWhere(
        (e) => e.name == json['privacy'],
        orElse: () => StoryPrivacy.contacts,
      ),
      customPrivacyList: (json['custom_privacy_list'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  /// Create a copy with updated fields
  Story copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatarUrl,
    String? mediaUrl,
    String? mediaMimeType,
    String? thumbnailUrl,
    StoryMediaType? mediaType,
    String? caption,
    String? textContent,
    DateTime? createdAt,
    DateTime? expiresAt,
    List<String>? viewedBy,
    StoryPrivacy? privacy,
    List<String>? customPrivacyList,
  }) {
    return Story(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaMimeType: mediaMimeType ?? this.mediaMimeType,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      mediaType: mediaType ?? this.mediaType,
      caption: caption ?? this.caption,
      textContent: textContent ?? this.textContent,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      viewedBy: viewedBy ?? this.viewedBy,
      privacy: privacy ?? this.privacy,
      customPrivacyList: customPrivacyList ?? this.customPrivacyList,
    );
  }
}

/// User's Story Collection (all stories from one user)
class UserStories {
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final List<Story> stories;

  UserStories({
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.stories,
  });

  /// Get only non-expired stories
  List<Story> get activeStories {
    return stories.where((s) => !s.isExpired).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Check if user has any active stories
  bool get hasActiveStories => activeStories.isNotEmpty;

  /// Check if all stories are viewed by specific user
  bool allViewedBy(String userId) {
    return activeStories.every((s) => s.isViewedBy(userId));
  }

  /// Get latest story
  Story? get latestStory {
    if (activeStories.isEmpty) return null;
    return activeStories.last;
  }

  /// Total view count across all stories
  int get totalViews {
    return activeStories.fold(0, (sum, story) => sum + story.viewCount);
  }
}

/// Story creation request
class CreateStoryRequest {
  final StoryMediaType mediaType;
  final Uint8List? mediaBytes; // Image or video bytes
  final String? mediaMimeType;
  final String? mediaFileName;
  final Uint8List? thumbnailBytes;
  final String? caption;
  final String? textContent; // For text-only stories
  final StoryPrivacy privacy;
  final List<String>? customPrivacyList;

  CreateStoryRequest({
    required this.mediaType,
    this.mediaBytes,
    this.mediaMimeType,
    this.mediaFileName,
    this.thumbnailBytes,
    this.caption,
    this.textContent,
    this.privacy = StoryPrivacy.contacts,
    this.customPrivacyList,
  });
}

/// Story view event
class StoryView {
  final String storyId;
  final String viewerId;
  final String viewerName;
  final DateTime viewedAt;

  StoryView({
    required this.storyId,
    required this.viewerId,
    required this.viewerName,
    required this.viewedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'story_id': storyId,
      'viewer_id': viewerId,
      'viewer_name': viewerName,
      'viewed_at': viewedAt.millisecondsSinceEpoch,
    };
  }

  factory StoryView.fromJson(Map<String, dynamic> json) {
    return StoryView(
      storyId: json['story_id'] as String,
      viewerId: json['viewer_id'] as String,
      viewerName: json['viewer_name'] as String,
      viewedAt: DateTime.fromMillisecondsSinceEpoch(json['viewed_at'] as int),
    );
  }
}
