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
  allUsers, // Legacy key: all existing direct chat contacts
  custom, // Custom list
  contactsExcept, // Direct chat contacts except selected users
}

/// Applies a story's audience rules to an existing direct-chat contact.
///
/// Distribution remains intentionally limited to direct-chat rooms. The
/// legacy [StoryPrivacy.allUsers] value means all contacts in that set, not
/// every account on the service.
bool canDirectContactViewStory(Story story, String userId) {
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

/// Individual Story Item
class Story {
  static const int currentFormatVersion = 1;
  static const int maxIdLength = 160;
  static const int maxUserIdLength = 255;
  static const int maxUserNameLength = 160;
  static const int maxUrlLength = 2048;
  static const int maxMimeTypeLength = 127;
  static const int maxCaptionLength = 1024;
  static const int maxTextLength = 5000;
  static const int maxAudienceEntries = 5000;
  static const int maxViewedByEntries = 10000;

  final int formatVersion;
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
    this.formatVersion = currentFormatVersion,
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
      'version': formatVersion,
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
    final story = Story.tryFromJson(json);
    if (story == null) {
      throw const FormatException('Invalid XMO story payload');
    }
    return story;
  }

  /// Parses untrusted account-data or room-event content.
  ///
  /// Version 1 also accepts legacy payloads that omitted `version`.
  static Story? tryFromJson(Map<String, dynamic> json) {
    final rawVersion = json['version'];
    final version = rawVersion == null
        ? currentFormatVersion
        : _boundedInt(rawVersion, min: 1, max: currentFormatVersion);
    if (version == null) return null;
    final id = _boundedString(json['id'], maxIdLength);
    final userId = _boundedString(json['user_id'], maxUserIdLength);
    final userName = _boundedString(json['user_name'], maxUserNameLength);
    final mediaType = _enumByName(StoryMediaType.values, json['media_type']);
    final createdAtMs = _boundedInt(json['created_at'], min: 1);
    final expiresAtMs = _boundedInt(json['expires_at'], min: 1);
    if (id == null ||
        userId == null ||
        userName == null ||
        mediaType == null ||
        createdAtMs == null ||
        expiresAtMs == null ||
        expiresAtMs <= createdAtMs) {
      return null;
    }

    final mediaUrl = _optionalBoundedString(json['media_url'], maxUrlLength);
    final thumbnailUrl =
        _optionalBoundedString(json['thumbnail_url'], maxUrlLength);
    final mediaMimeType =
        _optionalBoundedString(json['media_mime_type'], maxMimeTypeLength);
    final caption =
        _optionalBoundedString(json['caption'], maxCaptionLength, trim: false);
    final textContent = _optionalBoundedString(
      json['text_content'],
      maxTextLength,
      trim: false,
    );
    final userAvatarUrl =
        _optionalBoundedString(json['user_avatar_url'], maxUrlLength);
    if (mediaUrl == _invalidOptionalString ||
        thumbnailUrl == _invalidOptionalString ||
        mediaMimeType == _invalidOptionalString ||
        caption == _invalidOptionalString ||
        textContent == _invalidOptionalString ||
        userAvatarUrl == _invalidOptionalString) {
      return null;
    }

    if (mediaType == StoryMediaType.text) {
      if (textContent == null || textContent.trim().isEmpty) return null;
    } else if (mediaUrl == null || !_isMxcUrl(mediaUrl)) {
      return null;
    }
    if (thumbnailUrl != null && !_isMxcUrl(thumbnailUrl)) return null;

    final viewedBy = _boundedStringList(
      json['viewed_by'],
      maxItems: maxViewedByEntries,
      maxLength: maxUserIdLength,
    );
    final customPrivacyList = _boundedStringList(
      json['custom_privacy_list'],
      maxItems: maxAudienceEntries,
      maxLength: maxUserIdLength,
      nullable: true,
    );
    if (viewedBy == null ||
        (json['custom_privacy_list'] != null && customPrivacyList == null)) {
      return null;
    }

    final privacy = _enumByName(StoryPrivacy.values, json['privacy']) ??
        StoryPrivacy.contacts;

    return Story(
      formatVersion: version,
      id: id,
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      mediaUrl: mediaUrl,
      mediaMimeType: mediaMimeType,
      thumbnailUrl: thumbnailUrl,
      mediaType: mediaType,
      caption: caption,
      textContent: textContent,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
      viewedBy: viewedBy,
      privacy: privacy,
      customPrivacyList: customPrivacyList,
    );
  }

  /// Create a copy with updated fields
  Story copyWith({
    int? formatVersion,
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
      formatVersion: formatVersion ?? this.formatVersion,
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

  static const String _invalidOptionalString = '\u0000';

  static String? _boundedString(Object? value, int maxLength) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }

  static String? _optionalBoundedString(
    Object? value,
    int maxLength, {
    bool trim = true,
  }) {
    if (value == null) return null;
    if (value is! String || value.length > maxLength) {
      return _invalidOptionalString;
    }
    final result = trim ? value.trim() : value;
    return result.isEmpty ? null : result;
  }

  static int? _boundedInt(Object? value, {required int min, int? max}) {
    final parsed = switch (value) {
      int number => number,
      num number => number.toInt(),
      _ => int.tryParse(value?.toString() ?? ''),
    };
    if (parsed == null || parsed < min || max != null && parsed > max) {
      return null;
    }
    return parsed;
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static List<String>? _boundedStringList(
    Object? value, {
    required int maxItems,
    required int maxLength,
    bool nullable = false,
  }) {
    if (value == null) return nullable ? null : <String>[];
    if (value is! List || value.length > maxItems) return null;
    final result = <String>[];
    final seen = <String>{};
    for (final item in value) {
      final parsed = _boundedString(item, maxLength);
      if (parsed == null) return null;
      if (seen.add(parsed)) result.add(parsed);
    }
    return result;
  }

  static bool _isMxcUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'mxc' &&
        uri.host.isNotEmpty &&
        uri.pathSegments.isNotEmpty;
  }
}

/// User's Story Collection (all stories from one user)
class UserStories {
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final List<Story> stories;
  final DateTime? snapshotUpdatedAt;

  UserStories({
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.stories,
    this.snapshotUpdatedAt,
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

/// Returns whether [incoming] is safe to apply over [current].
///
/// Story updates contain the owner's complete active story list. Matrix sync
/// can deliver older timeline events after newer ones, so list arrival order
/// cannot be used as snapshot order.
bool shouldReplaceStorySnapshot(
  UserStories current,
  UserStories incoming,
) {
  final currentVersion = current.snapshotUpdatedAt;
  final incomingVersion = incoming.snapshotUpdatedAt;

  if (currentVersion != null && incomingVersion != null) {
    final comparison = incomingVersion.compareTo(currentVersion);
    if (comparison != 0) return comparison > 0;
  } else if (incomingVersion != null) {
    return true;
  }

  final currentLatest = current.latestStory?.createdAt;
  final incomingLatest = incoming.latestStory?.createdAt;
  if (currentLatest != null && incomingLatest != null) {
    final comparison = incomingLatest.compareTo(currentLatest);
    if (comparison != 0) return comparison > 0;
  } else if (incomingLatest != null) {
    return true;
  } else if (currentLatest != null) {
    // An empty snapshot may delete all stories only when it has a newer
    // explicit version. Legacy unversioned empty snapshots are ambiguous.
    return incomingVersion != null && currentVersion == null;
  }

  final currentIds = current.stories.map((story) => story.id).toSet();
  final incomingIds = incoming.stories.map((story) => story.id).toSet();
  return incomingIds.containsAll(currentIds);
}

/// Story creation request
class CreateStoryRequest {
  final String? clientRequestId;
  final StoryMediaType mediaType;
  final Uint8List? mediaBytes; // Image or video bytes
  final String? mediaFilePath; // File-backed media, used for large videos
  final int? mediaSizeBytes;
  final String? mediaMimeType;
  final String? mediaFileName;
  final Uint8List? thumbnailBytes;
  final String? caption;
  final String? textContent; // For text-only stories
  final StoryPrivacy privacy;
  final List<String>? customPrivacyList;

  CreateStoryRequest({
    this.clientRequestId,
    required this.mediaType,
    this.mediaBytes,
    this.mediaFilePath,
    this.mediaSizeBytes,
    this.mediaMimeType,
    this.mediaFileName,
    this.thumbnailBytes,
    this.caption,
    this.textContent,
    this.privacy = StoryPrivacy.contacts,
    this.customPrivacyList,
  });

  bool get hasMedia =>
      (mediaBytes != null && mediaBytes!.isNotEmpty) ||
      (mediaFilePath != null && mediaFilePath!.trim().isNotEmpty);
}

enum StoryCreationPhase {
  preparing,
  uploadingMedia,
  uploadingThumbnail,
  publishing,
}

class StoryCreationProgress {
  final StoryCreationPhase phase;
  final int uploadedBytes;
  final int totalBytes;

  const StoryCreationProgress({
    required this.phase,
    this.uploadedBytes = 0,
    this.totalBytes = 0,
  });

  double? get fraction => totalBytes > 0
      ? (uploadedBytes / totalBytes).clamp(0.0, 1.0).toDouble()
      : null;
}

class StoryCreationCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class StoryCreationCancelledException implements Exception {
  const StoryCreationCancelledException();

  @override
  String toString() => 'Story upload cancelled';
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

/// A validated story-view receipt.
///
/// The event sender is authoritative. The optional `viewer_id` in event
/// content is retained for compatibility but must not disagree with it.
class StoryViewReceipt {
  final String storyId;
  final String viewerId;
  final DateTime viewedAt;

  const StoryViewReceipt({
    required this.storyId,
    required this.viewerId,
    required this.viewedAt,
  });
}

StoryViewReceipt? parseStoryViewReceipt({
  required Map<String, dynamic> content,
  required String senderId,
  required DateTime receivedAt,
}) {
  final rawStoryId = content['story_id'];
  final storyId = rawStoryId is String ? rawStoryId.trim() : null;
  final actualViewerId = senderId.trim();
  if (storyId == null ||
      storyId.isEmpty ||
      storyId.length > Story.maxIdLength ||
      actualViewerId.isEmpty ||
      actualViewerId.length > Story.maxUserIdLength) {
    return null;
  }

  final rawClaimedViewerId = content['viewer_id'];
  if (rawClaimedViewerId != null && rawClaimedViewerId is! String) {
    return null;
  }
  final claimedViewerId =
      rawClaimedViewerId is String ? rawClaimedViewerId.trim() : null;
  if (claimedViewerId != null && claimedViewerId.isNotEmpty) {
    if (claimedViewerId.length > Story.maxUserIdLength ||
        claimedViewerId != actualViewerId) {
      return null;
    }
  }

  return StoryViewReceipt(
    storyId: storyId,
    viewerId: actualViewerId,
    viewedAt: receivedAt,
  );
}
