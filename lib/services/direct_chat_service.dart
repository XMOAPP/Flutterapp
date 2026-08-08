import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import '../models/direct_chat_models.dart';
import '../utils/matrix_identity.dart';
import 'matrix_service.dart';

/// Service for managing direct chat (DM) features
class DirectChatService {
  final MatrixService _matrixService;

  DirectChatService(this._matrixService);

  Client get _client => _matrixService.client;

  // ═══════════════════════════════════════════════════════════════════════════
  // USER PROFILE & STATUS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets user profile for direct chat
  Future<DirectChatProfile> getUserProfile(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final user = room.getParticipants().firstWhere(
      (u) => u.id == userId,
      orElse: () => throw Exception('User not found'),
    );

    // Get shared media count
    final timeline = await room.getTimeline();
    final mediaCount = timeline.events.where((e) {
      if (e.redacted) return false;
      final msgType = e.messageType;
      return msgType == MessageTypes.Image ||
          msgType == MessageTypes.Video ||
          msgType == MessageTypes.Audio ||
          msgType == MessageTypes.File;
    }).length;

    // Get first message date
    final firstMessage = timeline.events.isNotEmpty
        ? timeline.events.last.originServerTs
        : null;

    final rawDisplayName = user.displayName?.trim();
    final resolvedRoomName = _matrixService.getResolvedDisplayName(room).trim();
    final displayName =
        MatrixIdentity.isFriendlyDisplayName(rawDisplayName, user.id)
        ? rawDisplayName!
        : MatrixIdentity.isFriendlyDisplayName(resolvedRoomName, user.id)
        ? resolvedRoomName
        : MatrixIdentity.displayName(userId: user.id);

    return DirectChatProfile(
      userId: user.id,
      displayName: displayName,
      avatarUrl: user.avatarUrl?.toString(),
      isOnline: false, // Will be fetched separately
      lastSeen: null, // Will be fetched separately
      sharedMediaCount: mediaCount,
      firstMessageDate: firstMessage,
    );
  }

  /// Checks if user is online
  Future<bool> isUserOnline(String userId) async {
    try {
      final presence = await _client.getPresence(userId);
      return presence.presence == PresenceType.online;
    } catch (e) {
      debugPrint('[DirectChat] Error checking online status: $e');
      return false;
    }
  }

  /// Gets user's last seen time
  Future<DateTime?> getLastSeen(String userId) async {
    try {
      final presence = await _client.getPresence(userId);
      return presence.lastActiveAgo != null
          ? DateTime.now().subtract(
              Duration(milliseconds: presence.lastActiveAgo!),
            )
          : null;
    } catch (e) {
      debugPrint('[DirectChat] Error getting last seen: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED MEDIA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets all shared media in direct chat
  Future<List<SharedMediaItem>> getSharedMedia(
    String roomId, {
    MediaType? filterType,
    Timeline? timeline,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final sourceTimeline = timeline ?? await room.getTimeline();
    final mediaEvents = sourceTimeline.events.where((e) {
      if (e.redacted) return false;
      final msgType = e.messageType;
      return msgType == MessageTypes.Image ||
          msgType == MessageTypes.Video ||
          msgType == MessageTypes.Audio ||
          msgType == MessageTypes.File;
    }).toList();

    var mediaItems = mediaEvents
        .map((e) => SharedMediaItem.fromEvent(e))
        .toList();

    // Filter by type if specified
    if (filterType != null) {
      mediaItems = mediaItems.where((item) => item.type == filterType).toList();
    }

    // Sort by timestamp (newest first)
    mediaItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return mediaItems;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAT SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets chat settings
  Future<DirectChatSettings> getChatSettings(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    // Get settings from room state
    final settingsState = room.getState('xmo.chat.settings');
    final isMuted = room.pushRuleState == PushRuleState.dontNotify;

    if (settingsState == null) {
      return DirectChatSettings(isMuted: isMuted);
    }

    final content = settingsState.content;
    return DirectChatSettings(
      isMuted: isMuted,
      notificationsEnabled: content['notifications_enabled'] as bool? ?? true,
      readReceiptsEnabled: content['read_receipts_enabled'] as bool? ?? true,
      typingIndicatorsEnabled:
          content['typing_indicators_enabled'] as bool? ?? true,
      customWallpaper: content['custom_wallpaper'] as String?,
      disappearingMessagesEnabled:
          content['disappearing_messages_enabled'] as bool? ?? false,
    );
  }

  /// Updates chat settings
  Future<void> updateChatSettings(
    String roomId,
    DirectChatSettings settings,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    // Update mute status
    if (settings.isMuted) {
      await room.setPushRuleState(PushRuleState.dontNotify);
    } else {
      await room.setPushRuleState(PushRuleState.notify);
    }

    // Update other settings in room state
    await room.client.setRoomStateWithKey(roomId, 'xmo.chat.settings', '', {
      'notifications_enabled': settings.notificationsEnabled,
      'read_receipts_enabled': settings.readReceiptsEnabled,
      'typing_indicators_enabled': settings.typingIndicatorsEnabled,
      'custom_wallpaper': settings.customWallpaper,
      'disappearing_messages_enabled': settings.disappearingMessagesEnabled,
    });
  }

  /// Mutes/unmutes chat
  Future<void> toggleMute(String roomId, bool mute) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    if (mute) {
      await room.setPushRuleState(PushRuleState.dontNotify);
    } else {
      await room.setPushRuleState(PushRuleState.notify);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BLOCK/UNBLOCK
  // ═══════════════════════════════════════════════════════════════════════════

  /// Blocks a user
  Future<void> blockUser(String userId) async {
    debugPrint('[DirectChat] Blocking user: $userId');
    // Matrix doesn't have native block, so we'll use ignore list
    await _client.ignoreUser(userId);
  }

  /// Unblocks a user
  Future<void> unblockUser(String userId) async {
    debugPrint('[DirectChat] Unblocking user: $userId');
    await _client.unignoreUser(userId);
  }

  /// Checks if user is blocked
  bool isUserBlocked(String userId) {
    return _client.ignoredUsers.contains(userId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MESSAGE REACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Adds reaction to message
  Future<void> addReaction(String roomId, String eventId, String emoji) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    debugPrint('[DirectChat] Adding reaction $emoji to $eventId');
    await room.sendReaction(eventId, emoji);
  }

  /// Removes reaction from message
  Future<void> removeReaction(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    // Find the reaction event
    final timeline = await room.getTimeline();
    final myUserId = _client.userID;

    for (final e in timeline.events) {
      if (e.type == EventTypes.Reaction && e.senderId == myUserId) {
        final relatesTo = e.content['m.relates_to'] as Map<String, dynamic>?;
        if (relatesTo?['event_id'] == eventId) {
          await room.redactEvent(e.eventId);
          return;
        }
      }
    }

    throw Exception('Reaction not found');
  }

  /// Gets reactions for a message
  List<MessageReaction> getReactions(Event event) {
    final reactions = <MessageReaction>[];

    // For now, return empty list as reactions are handled by Matrix SDK internally
    // This method can be enhanced later when we need to display reactions in UI
    return reactions;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TYPING INDICATORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sends typing indicator
  Future<void> sendTypingIndicator(String roomId, bool typing) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    await room.setTyping(typing);
  }

  /// Gets list of users currently typing
  List<TypingIndicator> getTypingUsers(Room room) {
    final typingUsers = room.typingUsers;
    final myUserId = _client.userID;

    return typingUsers
        .where((user) => user.id != myUserId)
        .map(
          (user) => TypingIndicator(
            userId: user.id,
            displayName: MatrixIdentity.displayName(
              userId: user.id,
              candidate: user.displayName,
            ),
            startedAt: DateTime.now(), // Matrix doesn't provide exact time
          ),
        )
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clears chat history
  Future<void> clearChatHistory(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    debugPrint('[DirectChat] Clearing chat history for $roomId');

    // Get all messages
    final timeline = await room.getTimeline();
    final messages = timeline.events
        .where((e) => !e.redacted && e.type == EventTypes.Message)
        .toList();

    // Redact all messages
    for (final message in messages) {
      try {
        await room.redactEvent(message.eventId);
      } catch (e) {
        debugPrint('[DirectChat] Failed to redact ${message.eventId}: $e');
      }
    }
  }

  /// Exports chat history
  Future<String> exportChat(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final timeline = await room.getTimeline();
    final messages = timeline.events
        .where((e) => !e.redacted && e.type == EventTypes.Message)
        .toList();

    final buffer = StringBuffer();
    buffer.writeln(
      'Chat Export: ${_matrixService.getResolvedDisplayName(room)}',
    );
    buffer.writeln('Exported: ${DateTime.now()}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    for (final message in messages.reversed) {
      final sender = MatrixService.cleanName(message.senderId);
      final time = message.originServerTs;
      final text = message.body;

      buffer.writeln('[$time] $sender: $text');
    }

    return buffer.toString();
  }

  /// Searches messages in chat
  Future<List<Event>> searchMessages(String roomId, String query) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final timeline = await room.getTimeline();
    final lowerQuery = query.toLowerCase();

    return timeline.events
        .where(
          (e) =>
              !e.redacted &&
              e.type == EventTypes.Message &&
              e.body.toLowerCase().contains(lowerQuery),
        )
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // READ RECEIPTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sends read receipt
  Future<void> sendReadReceipt(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    await room.setReadMarker(eventId, mRead: eventId);
  }

  /// Checks if message has been read
  bool isMessageRead(Event event, Room room, {List<Event>? timelineEvents}) {
    final otherUserId = room.directChatMatrixID;

    if (otherUserId == null) return false;

    try {
      final hasExactReceipt = event.receipts.any(
        (receipt) => receipt.user.senderId == otherUserId,
      );
      if (hasExactReceipt) return true;

      final latestReadEventId =
          room.receiptState.global.otherUsers[otherUserId]?.eventId;
      if (latestReadEventId == null || latestReadEventId.isEmpty) {
        return false;
      }
      if (latestReadEventId == event.eventId) return true;

      final events = timelineEvents;
      if (events == null || events.isEmpty) return false;

      final latestReadEvent = events
          .where((candidate) => candidate.eventId == latestReadEventId)
          .firstOrNull;
      if (latestReadEvent == null) return false;

      return !event.originServerTs.isAfter(latestReadEvent.originServerTs);
    } catch (e) {
      debugPrint('[DirectChat] Error checking read status: $e');
      return false;
    }
  }
}
