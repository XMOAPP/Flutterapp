import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import '../models/channel_models.dart';
import '../utils/matrix_identity.dart';
import 'matrix_service.dart';
import 'room_controls_service.dart';
import 'channel_analytics_service.dart';

/// Service for managing channel-specific features
/// Channels are broadcast-only rooms where only admins can post
class ChannelService {
  final MatrixService _matrixService;
  late final ChannelAnalyticsService _analyticsService;

  ChannelService(this._matrixService) {
    _analyticsService = ChannelAnalyticsService(_matrixService.client);
  }

  Client get _client => _matrixService.client;

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets channel settings
  Future<ChannelSettings> getChannelSettings(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    // Get sign messages setting from custom state
    final signMessagesState = room.getState('xmo.channel.settings');
    final signMessages =
        signMessagesState?.content['sign_messages'] as bool? ?? true;

    // Get linked discussion group
    final linkedGroupState = room.getState('xmo.channel.discussion');
    final linkedGroupId = linkedGroupState?.content['group_id'] as String?;

    return ChannelSettings(
      name: room.name,
      description: room.topic,
      avatarUrl: room.avatar?.toString(),
      isPublic: RoomControlsService.isPublicUnencrypted(room),
      signMessages: signMessages,
      linkedDiscussionGroupId: linkedGroupId,
      allowComments: linkedGroupId != null,
    );
  }

  /// Updates channel settings
  Future<void> updateChannelSettings(
    String roomId,
    ChannelSettings settings,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    debugPrint('[ChannelService] Updating channel settings for $roomId');

    // Update name
    if (settings.name.isNotEmpty && settings.name != room.name) {
      await room.setName(settings.name);
    }

    // Update description
    if (settings.description != null && settings.description != room.topic) {
      await room.setDescription(settings.description!);
    }

    // Update avatar
    if (settings.avatarUrl != null) {
      // Avatar update handled separately via setAvatar
    }

    // Channel public/private security type is permanent after creation.
    final immutableJoinMode = RoomControlsService.immutableJoinModeFor(room);
    await RoomControlsService.setChannelJoinMode(room, immutableJoinMode);
    await RoomControlsService.setChannelDirectoryVisibility(
      room,
      immutableJoinMode,
    );

    // Update sign messages setting
    await room.client.setRoomStateWithKey(roomId, 'xmo.channel.settings', '', {
      'sign_messages': settings.signMessages,
    });

    // Update linked discussion group
    if (settings.linkedDiscussionGroupId != null) {
      await room.client.setRoomStateWithKey(
        roomId,
        'xmo.channel.discussion',
        '',
        {'group_id': settings.linkedDiscussionGroupId},
      );
    }

    debugPrint('[ChannelService] Channel settings updated');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUBSCRIBER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets all channel subscribers
  Future<List<ChannelSubscriber>> getSubscribers(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    await room.requestParticipants();
    final participants = room.getParticipants();

    return participants
        .map((user) => ChannelSubscriber.fromUser(user, room))
        .toList()
      ..sort((a, b) {
        // Sort: admins first, then by name
        if (a.isAdmin != b.isAdmin) {
          return a.isAdmin ? -1 : 1;
        }
        return a.displayName.compareTo(b.displayName);
      });
  }

  /// Gets subscriber count
  Future<int> getSubscriberCount(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    return room.summary.mJoinedMemberCount ?? 0;
  }

  /// Bans a subscriber
  Future<void> banSubscriber(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    debugPrint('[ChannelService] Banning subscriber $userId from $roomId');
    await room.ban(userId);
  }

  /// Unbans a subscriber
  Future<void> unbanSubscriber(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    debugPrint('[ChannelService] Unbanning subscriber $userId from $roomId');
    await room.unban(userId);
  }

  /// Gets banned subscribers
  Future<List<ChannelSubscriber>> getBannedSubscribers(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    final bannedUsers = <ChannelSubscriber>[];
    final memberStates = room.states[EventTypes.RoomMember];

    if (memberStates != null) {
      for (final state in memberStates.values) {
        if (state.content['membership'] == 'ban') {
          final userId = state.stateKey!;
          final displayName = state.content['displayname'];
          final avatarUrl = state.content['avatar_url'];
          bannedUsers.add(
            ChannelSubscriber(
              userId: userId,
              displayName: MatrixIdentity.displayName(
                userId: userId,
                candidate: displayName is String ? displayName : null,
              ),
              avatarUrl: avatarUrl is String ? avatarUrl : null,
              joinedAt: state is Event ? state.originServerTs : DateTime.now(),
              isBanned: true,
              isAdmin: false,
              powerLevel: -1,
            ),
          );
        }
      }
    }

    return bannedUsers;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADMIN MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets all channel admins
  Future<List<ChannelAdmin>> getAdmins(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    await room.requestParticipants();
    final participants = room.getParticipants();

    return participants
        .where((user) => user.powerLevel >= PowerLevel.moderator)
        .map((user) => ChannelAdmin.fromUser(user))
        .toList()
      ..sort((a, b) => b.powerLevel.compareTo(a.powerLevel));
  }

  /// Promotes a subscriber to admin
  Future<void> promoteToAdmin(
    String roomId,
    String userId,
    ChannelAdminPermissions permissions,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    final powerLevel = permissions.toPowerLevel();
    debugPrint('[ChannelService] Promoting $userId to power level $powerLevel');

    await room.setPower(userId, powerLevel);
  }

  /// Demotes an admin to subscriber
  Future<void> demoteAdmin(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    debugPrint('[ChannelService] Demoting $userId to subscriber');
    await room.setPower(userId, 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets channel statistics
  Future<ChannelStatistics> getStatistics(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    // Get subscriber count
    final subscriberCount = room.summary.mJoinedMemberCount ?? 0;

    // Get timeline to count posts
    final timeline = await room.getTimeline();
    final posts = timeline.events
        .where((e) => e.type == EventTypes.Message)
        .toList();

    final now = DateTime.now();
    final last24h = now.subtract(const Duration(hours: 24));
    final last7days = now.subtract(const Duration(days: 7));

    final postsLast24h = posts
        .where((e) => e.originServerTs.isAfter(last24h))
        .length;

    final postsLast7days = posts
        .where((e) => e.originServerTs.isAfter(last7days))
        .length;

    var averageViews = 0;
    try {
      final analytics = await _analyticsService.getStatistics(
        roomId,
        eventIds: posts.map((post) => post.eventId),
      );
      averageViews = analytics.averageViews.round();
    } catch (error) {
      debugPrint('[ChannelService] Analytics unavailable: $error');
    }

    return ChannelStatistics(
      totalSubscribers: subscriberCount,
      totalPosts: posts.length,
      postsLast24h: postsLast24h,
      postsLast7days: postsLast7days,
      averageViews: averageViews,
      createdAt: room.getState(EventTypes.RoomCreate) is Event
          ? (room.getState(EventTypes.RoomCreate) as Event).originServerTs
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Gets post statistics
  Future<PostStatistics?> getPostStatistics(
    String roomId,
    String eventId,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;

    final event = await room.getEventById(eventId);
    if (event == null) return null;

    var analytics = const ChannelPostAnalytics(views: 0, forwards: 0);
    try {
      analytics = (await _analyticsService.getStatistics(
        roomId,
        eventIds: [eventId],
      )).analyticsFor(eventId);
    } catch (error) {
      debugPrint('[ChannelService] Post analytics unavailable: $error');
    }
    return PostStatistics(
      eventId: eventId,
      views: analytics.views,
      forwards: analytics.forwards,
      postedAt: event.originServerTs,
      postedBy: event.senderId,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INVITE LINKS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generates a channel invite link
  Future<ChannelInviteLink> generateInviteLink(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    final link = await _matrixService.generateTrackedInviteLink(roomId);

    return ChannelInviteLink(
      linkId: link.linkId,
      url: link.url,
      channelId: roomId,
      createdAt: link.createdAt,
      expiresAt: link.expiresAt,
      createdBy: link.createdBy,
      usedCount: link.usedCount,
      isActive: link.isActive,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL POSTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Posts a message to the channel (admin only)
  Future<void> postMessage(
    String roomId,
    String text, {
    bool signMessage = true,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    // Check if user has permission to post
    if (room.ownPowerLevel < PowerLevel.moderator) {
      throw Exception('Only admins can post to channels');
    }

    await room.sendTextEvent(text);
  }

  /// Deletes a channel permanently
  Future<void> deleteChannel(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Channel not found: $roomId');

    debugPrint('[ChannelService] Deleting channel: $roomId');

    // Get all subscribers
    await room.requestParticipants();
    final participants = room.getParticipants();

    // Kick all subscribers except self
    final myUserId = _client.userID;
    for (final user in participants) {
      if (user.id != myUserId) {
        try {
          await room.kick(user.id);
          debugPrint('[ChannelService] Kicked ${user.id}');
        } catch (e) {
          debugPrint('[ChannelService] Failed to kick ${user.id}: $e');
        }
      }
    }

    // Leave and forget the room
    try {
      await room.leave();
      await room.forget();
      debugPrint('[ChannelService] Channel deleted successfully');
    } catch (e) {
      debugPrint('[ChannelService] Failed to delete channel: $e');
    }
  }
}
