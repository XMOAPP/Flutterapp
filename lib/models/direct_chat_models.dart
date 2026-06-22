import 'package:matrix/matrix.dart';

/// Models for direct chat (DM) features

/// User profile information for direct chats
class DirectChatProfile {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isBlocked;
  final bool isMuted;
  final int sharedMediaCount;
  final DateTime? firstMessageDate;

  DirectChatProfile({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.isOnline = false,
    this.lastSeen,
    this.isBlocked = false,
    this.isMuted = false,
    this.sharedMediaCount = 0,
    this.firstMessageDate,
  });

  factory DirectChatProfile.fromUser(User user, Room room) {
    return DirectChatProfile(
      userId: user.id,
      displayName: user.displayName ?? user.id,
      avatarUrl: user.avatarUrl?.toString(),
      isOnline: false, // Will be fetched separately via presence API
      lastSeen: null, // Will be fetched separately via presence API
    );
  }
}

/// Shared media item in direct chat
class SharedMediaItem {
  final String eventId;
  final MediaType type;
  final String? thumbnailUrl;
  final String? url;
  final String filename;
  final int? fileSize;
  final DateTime timestamp;
  final String senderId;

  SharedMediaItem({
    required this.eventId,
    required this.type,
    this.thumbnailUrl,
    this.url,
    required this.filename,
    this.fileSize,
    required this.timestamp,
    required this.senderId,
  });

  factory SharedMediaItem.fromEvent(Event event) {
    final messageType = event.messageType;
    MediaType type;

    if (messageType == MessageTypes.Image) {
      type = MediaType.image;
    } else if (messageType == MessageTypes.Video) {
      type = MediaType.video;
    } else if (messageType == MessageTypes.Audio) {
      type = MediaType.audio;
    } else {
      type = MediaType.file;
    }

    final content = event.content;
    final info = content['info'] as Map<String, dynamic>?;

    return SharedMediaItem(
      eventId: event.eventId,
      type: type,
      url: content['url'] as String?,
      thumbnailUrl: info?['thumbnail_url'] as String?,
      filename: event.body,
      fileSize: info?['size'] as int?,
      timestamp: event.originServerTs,
      senderId: event.senderId,
    );
  }
}

enum MediaType {
  image,
  video,
  audio,
  file,
}

/// Chat settings for direct chat
class DirectChatSettings {
  final bool isMuted;
  final bool notificationsEnabled;
  final bool readReceiptsEnabled;
  final bool typingIndicatorsEnabled;
  final String? customWallpaper;
  final String? customNotificationSound;
  final bool disappearingMessagesEnabled;
  final Duration? disappearingMessagesDuration;

  DirectChatSettings({
    this.isMuted = false,
    this.notificationsEnabled = true,
    this.readReceiptsEnabled = true,
    this.typingIndicatorsEnabled = true,
    this.customWallpaper,
    this.customNotificationSound,
    this.disappearingMessagesEnabled = false,
    this.disappearingMessagesDuration,
  });

  DirectChatSettings copyWith({
    bool? isMuted,
    bool? notificationsEnabled,
    bool? readReceiptsEnabled,
    bool? typingIndicatorsEnabled,
    String? customWallpaper,
    String? customNotificationSound,
    bool? disappearingMessagesEnabled,
    Duration? disappearingMessagesDuration,
  }) {
    return DirectChatSettings(
      isMuted: isMuted ?? this.isMuted,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
      typingIndicatorsEnabled:
          typingIndicatorsEnabled ?? this.typingIndicatorsEnabled,
      customWallpaper: customWallpaper ?? this.customWallpaper,
      customNotificationSound:
          customNotificationSound ?? this.customNotificationSound,
      disappearingMessagesEnabled:
          disappearingMessagesEnabled ?? this.disappearingMessagesEnabled,
      disappearingMessagesDuration:
          disappearingMessagesDuration ?? this.disappearingMessagesDuration,
    );
  }
}

/// Message reaction
class MessageReaction {
  final String eventId;
  final String reaction;
  final String userId;
  final DateTime timestamp;

  MessageReaction({
    required this.eventId,
    required this.reaction,
    required this.userId,
    required this.timestamp,
  });
}

/// Voice message
class VoiceMessage {
  final String eventId;
  final String url;
  final Duration duration;
  final int fileSize;
  final DateTime timestamp;
  final String senderId;
  final bool isPlaying;
  final Duration currentPosition;

  VoiceMessage({
    required this.eventId,
    required this.url,
    required this.duration,
    required this.fileSize,
    required this.timestamp,
    required this.senderId,
    this.isPlaying = false,
    this.currentPosition = Duration.zero,
  });

  VoiceMessage copyWith({
    bool? isPlaying,
    Duration? currentPosition,
  }) {
    return VoiceMessage(
      eventId: eventId,
      url: url,
      duration: duration,
      fileSize: fileSize,
      timestamp: timestamp,
      senderId: senderId,
      isPlaying: isPlaying ?? this.isPlaying,
      currentPosition: currentPosition ?? this.currentPosition,
    );
  }
}

/// Message draft
class MessageDraft {
  final String roomId;
  final String text;
  final DateTime savedAt;
  final String? replyToEventId;

  MessageDraft({
    required this.roomId,
    required this.text,
    required this.savedAt,
    this.replyToEventId,
  });
}

/// Typing indicator
class TypingIndicator {
  final String userId;
  final String displayName;
  final DateTime startedAt;

  TypingIndicator({
    required this.userId,
    required this.displayName,
    required this.startedAt,
  });

  bool get isExpired {
    return DateTime.now().difference(startedAt).inSeconds > 5;
  }
}
