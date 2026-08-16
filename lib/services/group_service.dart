import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import '../config/media_upload_policy.dart';
import '../models/group_models.dart';
import '../models/matrix_mentions.dart';
import '../utils/matrix_identity.dart';
import 'matrix_service.dart';
import 'room_capacity_policy.dart';
import 'room_controls_service.dart';

/// Service for managing group-specific features
/// Extends Matrix rooms with Telegram-like group functionality
class GroupService {
  static const String _adminActionStateType = 'xmo.admin.action';
  static const String _memberRestrictionStateType = 'xmo.member.restriction';

  final MatrixService _matrixService;

  GroupService(this._matrixService);

  Client get _client => _matrixService.client;

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP CREATION & SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Creates a new group with specified settings
  Future<String> createGroup({
    required String name,
    String? description,
    GroupType type = GroupType.private,
    JoinRule joinRule = JoinRule.invite,
    bool historyVisible = true,
  }) async {
    debugPrint(
      '[GroupService] Creating group: $name (type: $type, joinRule: $joinRule)',
    );

    final effectiveJoinRule = type == GroupType.public
        ? JoinRule.open
        : JoinRule.invite;

    // Convert our enums to Matrix types
    final matrixVisibility = type == GroupType.public
        ? Visibility.public
        : Visibility.private;
    final matrixJoinRules = _convertJoinRule(effectiveJoinRule);
    const matrixHistoryVisibility = 'shared';

    // Create room with group settings
    final roomId = await _client.createRoom(
      name: name,
      topic: description,
      visibility: matrixVisibility,
      preset: type == GroupType.public
          ? CreateRoomPreset.publicChat
          : CreateRoomPreset.privateChat,
      initialState: type == GroupType.private
          ? _matrixService.privateRoomInitialState([
              // Mark as group (not channel)
              StateEvent(
                type: 'xmo.room.type',
                stateKey: '',
                content: {'is_group': true, 'is_channel': false},
              ),
              // Set join rules
              StateEvent(
                type: EventTypes.RoomJoinRules,
                stateKey: '',
                content: {'join_rule': matrixJoinRules},
              ),
              // Set history visibility
              StateEvent(
                type: EventTypes.HistoryVisibility,
                stateKey: '',
                content: {'history_visibility': matrixHistoryVisibility},
              ),
            ])
          : [
              // Mark as group (not channel)
              StateEvent(
                type: 'xmo.room.type',
                stateKey: '',
                content: {'is_group': true, 'is_channel': false},
              ),
              // Set join rules
              StateEvent(
                type: EventTypes.RoomJoinRules,
                stateKey: '',
                content: {'join_rule': matrixJoinRules},
              ),
              // Set history visibility
              StateEvent(
                type: EventTypes.HistoryVisibility,
                stateKey: '',
                content: {'history_visibility': matrixHistoryVisibility},
              ),
              _matrixService.publicRoomSecurityState(),
            ],
      powerLevelContentOverride: {
        'events_default': 0, // Everyone can send messages
        'users_default': 0, // Default user power level
        'invite': 50, // Moderators can invite
        'kick': 50, // Moderators can kick
        'ban': 50, // Moderators can ban
        'redact': 50, // Moderators can delete messages
        'state_default': 75, // Admins can change room state
        'events': {
          'm.room.name': 75,
          'm.room.topic': 75,
          'm.room.avatar': 75,
          'm.room.power_levels': 100,
          'm.room.pinned_events': 50,
          EventTypes.GroupCallMember: 0,
        },
      },
    );

    _matrixService.cacheGroupId(roomId);
    final room =
        _client.getRoomById(roomId) ?? Room(id: roomId, client: _client);
    await RoomControlsService.setRoomDirectoryVisibility(
      room,
      type == GroupType.public ? XmoJoinMode.public : XmoJoinMode.invite,
    );
    await _recordAdminAction(
      roomId,
      AdminActionType.settingsChanged,
      metadata: {
        'name': name,
        'type': type.name,
        'join_rule': effectiveJoinRule.name,
      },
    );
    debugPrint('[GroupService] Group created: $roomId');
    return roomId;
  }

  /// Updates group settings
  Future<void> updateGroupSettings(
    String roomId,
    GroupSettings settings,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    debugPrint('[GroupService] Updating group settings for $roomId');

    // Update name
    if (settings.name.isNotEmpty) {
      await room.setName(settings.name);
    }

    // Update description (topic)
    if (settings.description != null) {
      await room.setDescription(settings.description!);
    }

    // Update avatar
    if (settings.avatarUrl != null) {
      final avatarUrl = settings.avatarUrl!.trim();
      await updateGroupAvatar(
        roomId,
        removeAvatar: avatarUrl.isEmpty,
        avatarMxcUrl: avatarUrl.isEmpty ? null : avatarUrl,
      );
    }

    // Group public/private security type is permanent after creation.
    final immutableJoinMode = RoomControlsService.immutableJoinModeFor(room);
    await RoomControlsService.setJoinMode(room, immutableJoinMode);
    await RoomControlsService.setRoomDirectoryVisibility(
      room,
      immutableJoinMode,
    );

    // Update history visibility
    await room.client.setRoomStateWithKey(
      roomId,
      EventTypes.HistoryVisibility,
      '',
      {'history_visibility': 'shared'},
    );

    await _recordAdminAction(
      roomId,
      AdminActionType.settingsChanged,
      metadata: {
        'name': settings.name,
        'join_rule': settings.joinRule.name,
        'history_visible': true,
      },
    );
    debugPrint('[GroupService] Group settings updated');
  }

  /// Uploads, assigns, or removes the standard Matrix room avatar.
  ///
  /// Exactly one avatar operation must be supplied. Existing avatar URLs must
  /// be Matrix content URIs so arbitrary remote URLs are never stored as room
  /// avatar state.
  Future<void> updateGroupAvatar(
    String roomId, {
    Uint8List? avatarBytes,
    String avatarFileName = 'avatar.jpg',
    String? avatarMxcUrl,
    bool removeAvatar = false,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    if (!room.canChangeStateEvent(EventTypes.RoomAvatar)) {
      throw StateError('You do not have permission to change this avatar');
    }

    final hasBytes = avatarBytes != null;
    final hasMxcUrl = avatarMxcUrl != null;
    final operationCount =
        (hasBytes ? 1 : 0) + (hasMxcUrl ? 1 : 0) + (removeAvatar ? 1 : 0);
    if (operationCount != 1) {
      throw ArgumentError(
        'Provide exactly one avatar operation: bytes, MXC URL, or removal',
      );
    }

    Uri? avatarUri;
    if (hasBytes) {
      if (avatarBytes.isEmpty) {
        throw ArgumentError.value(
          avatarBytes,
          'avatarBytes',
          'Cannot be empty',
        );
      }
      MediaUploadPolicy.validate(avatarBytes.lengthInBytes);
      avatarUri = await room.client.uploadContent(
        avatarBytes,
        filename: avatarFileName,
        contentType: avatarContentTypeForFileName(avatarFileName),
      );
    } else if (hasMxcUrl) {
      avatarUri = parseAvatarMxcUrl(avatarMxcUrl);
    }

    if (avatarUri == room.avatar || (removeAvatar && room.avatar == null)) {
      return;
    }

    await room.client.setRoomStateWithKey(
      roomId,
      EventTypes.RoomAvatar,
      '',
      <String, dynamic>{if (avatarUri != null) 'url': avatarUri.toString()},
    );

    await _recordAdminAction(
      roomId,
      AdminActionType.settingsChanged,
      metadata: {'avatar': removeAvatar ? 'removed' : 'updated'},
    );
  }

  @visibleForTesting
  static String avatarContentTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  @visibleForTesting
  static Uri parseAvatarMxcUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'mxc' ||
        uri.host.isEmpty ||
        uri.pathSegments.isEmpty ||
        uri.pathSegments.every((segment) => segment.isEmpty)) {
      throw const FormatException('Avatar URL must be a valid mxc:// URI');
    }
    return uri;
  }

  /// Gets current group settings
  Future<GroupSettings> getGroupSettings(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final joinRulesState = room.getState(EventTypes.RoomJoinRules);
    return GroupSettings(
      name: room.name,
      description: room.topic,
      avatarUrl: room.avatar?.toString(),
      type: RoomControlsService.isPublicUnencrypted(room)
          ? GroupType.public
          : GroupType.private,
      joinRule: _convertToJoinRule(joinRulesState?.content['join_rule']),
      historyVisibleToNewMembers: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MEMBER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets all members of a group with their roles
  Future<List<GroupMember>> getGroupMembers(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    await room.requestParticipants();
    final participants = room.getParticipants();
    final restrictions = _activeRestrictionsByUser(room);

    return participants
        .map(
          (user) => GroupMember.fromUser(
            user,
            room,
          ).copyWith(restriction: restrictions[user.id]),
        )
        .toList()
      ..sort((a, b) {
        // Sort by power level (highest first), then by name
        if (a.powerLevel != b.powerLevel) {
          return b.powerLevel.compareTo(a.powerLevel);
        }
        return a.displayName.compareTo(b.displayName);
      });
  }

  /// Adds a member to the group
  Future<void> addMember(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    _ensureOwnPower(room, 50, 'invite members');
    await room.requestParticipants();
    RoomCapacityPolicy.ensureGroupHasSpace(room);

    debugPrint('[GroupService] Adding member $userId to $roomId');
    await room.invite(userId);
    await _recordAdminAction(
      roomId,
      AdminActionType.memberAdded,
      targetUser: userId,
    );
  }

  /// Removes a member from the group (kick)
  Future<void> removeMember(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    await _ensureCanModerateMember(room, userId, 'remove');

    debugPrint('[GroupService] Removing member $userId from $roomId');
    await room.kick(userId);
    await _recordAdminAction(
      roomId,
      AdminActionType.memberRemoved,
      targetUser: userId,
      metadata: {if (reason != null) 'reason': reason},
    );
  }

  /// Bans a member from the group
  Future<void> banMember(String roomId, String userId, {String? reason}) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    await _ensureCanModerateMember(room, userId, 'ban');

    debugPrint('[GroupService] Banning member $userId from $roomId');
    await room.ban(userId);
    await _recordAdminAction(
      roomId,
      AdminActionType.memberBanned,
      targetUser: userId,
      metadata: {if (reason != null) 'reason': reason},
    );
  }

  /// Unbans a member
  Future<void> unbanMember(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    debugPrint('[GroupService] Unbanning member $userId from $roomId');
    await room.unban(userId);
    await _recordAdminAction(
      roomId,
      AdminActionType.memberUnbanned,
      targetUser: userId,
    );
  }

  /// Gets banned members list
  Future<List<GroupMember>> getBannedMembers(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    // Get all member events with membership = 'ban'
    final bannedUsers = <GroupMember>[];
    final memberStates = room.states[EventTypes.RoomMember];

    if (memberStates != null) {
      for (final state in memberStates.values) {
        if (state.content['membership'] == 'ban') {
          final userId = state.stateKey!;
          final displayName = state.content['displayname'];
          final avatarUrl = state.content['avatar_url'];
          bannedUsers.add(
            GroupMember(
              userId: userId,
              displayName: MatrixIdentity.displayName(
                userId: userId,
                candidate: displayName is String ? displayName : null,
              ),
              avatarUrl: avatarUrl is String ? avatarUrl : null,
              role: MemberRole.restricted,
              powerLevel: -1,
              joinedAt: state is Event ? state.originServerTs : DateTime.now(),
              isBanned: true,
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

  /// Promotes a user to admin with specific permissions
  Future<void> promoteToAdmin(
    String roomId,
    String userId,
    AdminPermissions permissions,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final powerLevel = permissions.toPowerLevel();
    await _ensureCanChangePowerLevel(room, userId, powerLevel);
    debugPrint('[GroupService] Promoting $userId to power level $powerLevel');

    await room.setPower(userId, powerLevel);
    await _recordAdminAction(
      roomId,
      AdminActionType.memberPromoted,
      targetUser: userId,
      metadata: {'power_level': powerLevel},
    );
  }

  /// Demotes an admin to regular member
  Future<void> demoteAdmin(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    await _ensureCanChangePowerLevel(room, userId, 0);

    debugPrint('[GroupService] Demoting $userId to member');
    await room.setPower(userId, 0);
    await _recordAdminAction(
      roomId,
      AdminActionType.memberDemoted,
      targetUser: userId,
    );
  }

  /// Gets admin permissions for a user
  AdminPermissions getAdminPermissions(String roomId, String userId) {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final user = room.getParticipants().firstWhere(
      (u) => u.id == userId,
      orElse: () => throw Exception('User not found in room'),
    );

    return AdminPermissions.fromPowerLevel(user.powerLevel.level);
  }

  /// Gets all admins in the group
  Future<List<GroupMember>> getAdmins(String roomId) async {
    final members = await getGroupMembers(roomId);
    return members.where((m) => m.powerLevel >= 50).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PINNED MESSAGES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pins a message in the group
  Future<void> pinMessage(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    _ensureOwnPower(room, 50, 'pin messages');

    debugPrint('[GroupService] Pinning message $eventId in $roomId');

    // Get current pinned events
    final pinnedState = room.getState(EventTypes.RoomPinnedEvents);
    final pinnedContent = pinnedState?.content['pinned'];
    final currentPinned = pinnedContent is List
        ? List<String>.from(pinnedContent.cast<String>())
        : <String>[];

    // Add new pinned event if not already pinned
    if (!currentPinned.contains(eventId)) {
      currentPinned.add(eventId);
      await room.client.setRoomStateWithKey(
        roomId,
        EventTypes.RoomPinnedEvents,
        '',
        {'pinned': currentPinned},
      );
      await _recordAdminAction(
        roomId,
        AdminActionType.messagePinned,
        targetMessage: eventId,
      );
    }
  }

  /// Unpins a message
  Future<void> unpinMessage(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    _ensureOwnPower(room, 50, 'unpin messages');

    debugPrint('[GroupService] Unpinning message $eventId in $roomId');

    // Get current pinned events
    final pinnedState = room.getState(EventTypes.RoomPinnedEvents);
    final pinnedContent = pinnedState?.content['pinned'];
    final currentPinned = pinnedContent is List
        ? List<String>.from(pinnedContent.cast<String>())
        : <String>[];

    // Remove the event
    currentPinned.remove(eventId);
    await room.client.setRoomStateWithKey(
      roomId,
      EventTypes.RoomPinnedEvents,
      '',
      {'pinned': currentPinned},
    );
    await _recordAdminAction(
      roomId,
      AdminActionType.messageUnpinned,
      targetMessage: eventId,
    );
  }

  /// Gets all pinned messages
  Future<List<PinnedMessage>> getPinnedMessages(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final pinnedState = room.getState(EventTypes.RoomPinnedEvents);
    final pinnedContent = pinnedState?.content['pinned'];
    final pinnedEventIds = pinnedContent is List
        ? List<String>.from(pinnedContent.cast<String>())
        : <String>[];

    if (pinnedEventIds.isEmpty) return [];

    // Fetch the actual events
    final pinnedMessages = <PinnedMessage>[];
    for (final eventId in pinnedEventIds) {
      try {
        final event = await room.getEventById(eventId);
        if (event != null) {
          pinnedMessages.add(PinnedMessage.fromEvent(event));
        }
      } catch (e) {
        debugPrint('[GroupService] Failed to fetch pinned event $eventId: $e');
      }
    }

    return pinnedMessages;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPLIES & MENTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<AdminAction>> getAdminLog(
    String roomId, {
    Duration? since,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final cutoff = since == null ? null : DateTime.now().subtract(since);
    final actionStates = room.states[_adminActionStateType];
    if (actionStates == null) return const [];

    final actions =
        actionStates.values
            .map((state) => AdminAction.fromJson(state.content))
            .where((action) => action.actionId.isNotEmpty)
            .where(
              (action) => cutoff == null || action.timestamp.isAfter(cutoff),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return actions;
  }

  Future<void> restrictMember(
    String roomId,
    MemberRestriction restriction,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    await _ensureCanModerateMember(room, restriction.userId, 'restrict');

    await room.client.setRoomStateWithKey(
      roomId,
      _memberRestrictionStateType,
      restriction.userId,
      restriction.toJson(),
    );
    await _recordAdminAction(
      roomId,
      AdminActionType.memberRestricted,
      targetUser: restriction.userId,
      metadata: {
        'type': restriction.type.name,
        if (restriction.expiresAt != null)
          'expires_at': restriction.expiresAt!.toIso8601String(),
        if (restriction.reason != null) 'reason': restriction.reason,
      },
    );
  }

  Future<void> removeRestriction(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    await _ensureCanModerateMember(room, userId, 'remove restriction from');

    await room.client.setRoomStateWithKey(
      roomId,
      _memberRestrictionStateType,
      userId,
      {'removed': true, 'removed_at': DateTime.now().toIso8601String()},
    );
    await _recordAdminAction(
      roomId,
      AdminActionType.memberRestrictionRemoved,
      targetUser: userId,
    );
  }

  MemberRestriction? getMemberRestriction(String roomId, String userId) {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    return _restrictionFor(room, userId);
  }

  bool isReadOnlyRestricted(String roomId, String userId) {
    final restriction = getMemberRestriction(roomId, userId);
    return restriction != null &&
        restriction.type == RestrictionType.readOnly &&
        !restriction.isExpired;
  }

  /// Sends a reply to a specific message
  Future<void> sendReply(
    String roomId,
    String text,
    String replyToEventId,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    debugPrint('[GroupService] Sending reply to $replyToEventId');

    // Get the original event
    final originalEvent = await room.getEventById(replyToEventId);
    if (originalEvent == null) {
      throw Exception('Original message not found');
    }

    // Send message with reply relation
    await room.sendTextEvent(text, inReplyTo: originalEvent);
  }

  /// Sends a message with mentions
  Future<void> sendMention(
    String roomId,
    String text,
    List<String> mentionedUserIds,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    debugPrint(
      '[GroupService] Sending message with ${mentionedUserIds.length} mentions',
    );

    final mentionContent = MatrixMentions.forUserIds(
      mentionedUserIds,
      ownUserId: _client.userID,
    );
    if (mentionContent.isEmpty) {
      await room.sendTextEvent(text);
      return;
    }

    await room.sendEvent({
      'msgtype': MessageTypes.Text,
      'body': text,
      ...mentionContent,
    });
  }

  /// Gets the event a message is replying to
  Future<MessageReply?> getReplyInfo(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;

    final event = await room.getEventById(eventId);
    if (event == null) return null;

    final replyToId = event.relationshipEventId;
    if (replyToId == null) return null;

    final replyToEvent = await room.getEventById(replyToId);
    if (replyToEvent == null) return null;

    return MessageReply.fromEvent(replyToEvent);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  String _convertJoinRule(JoinRule rule) {
    switch (rule) {
      case JoinRule.open:
        return 'public';
      case JoinRule.invite:
        return 'invite';
      case JoinRule.knock:
        return 'knock';
    }
  }

  JoinRule _convertToJoinRule(dynamic matrixRule) {
    switch (matrixRule) {
      case 'public':
        return JoinRule.open;
      case 'knock':
        return JoinRule.knock;
      default:
        return JoinRule.invite;
    }
  }

  /// Checks if a room is a group (not a channel or DM)
  bool isGroup(Room room) {
    final kind = MatrixService.classifyRoomKind(
      typeContent: room.getState('xmo.room.type')?.content,
      powerLevelsContent: room.getState('m.room.power_levels')?.content,
      isDirectChat: room.isDirectChat,
      useGroupFallback: true,
    );
    if (kind == XmoRoomKind.group) {
      _matrixService.cacheGroupId(room.id);
      return true;
    }
    if (kind == XmoRoomKind.channel) {
      _matrixService.cacheChannelId(room.id);
      return false;
    }

    if (_matrixService.isKnownChannel(room.id)) return false;
    return _matrixService.isKnownGroup(room.id);
  }

  /// Checks if user has permission to perform an action
  bool hasPermission(Room room, String userId, String action) {
    final user = room.getParticipants().firstWhere(
      (u) => u.id == userId,
      orElse: () => throw Exception('User not found'),
    );

    final powerLevel = user.powerLevel.level;
    final powerLevelsState = room.getState(EventTypes.RoomPowerLevels);
    final actionLevel = powerLevelsState?.content[action];
    final requiredLevel = actionLevel is num ? actionLevel.toInt() : 50;

    return powerLevel >= requiredLevel;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP DELETION
  // ═══════════════════════════════════════════════════════════════════════════

  static bool canInviteMembers(int powerLevel) => powerLevel >= 50;

  static bool canPinMessages(int powerLevel) => powerLevel >= 50;

  static bool canModerateMembers(int powerLevel) => powerLevel >= 50;

  static bool canEditSettings(int powerLevel) => powerLevel >= 75;

  static bool canManageAdmins(int powerLevel) => powerLevel >= 100;

  static bool canActOnMember({
    required int actorPowerLevel,
    required int targetPowerLevel,
    int requiredPowerLevel = 50,
  }) {
    return actorPowerLevel >= requiredPowerLevel &&
        targetPowerLevel < 100 &&
        actorPowerLevel > targetPowerLevel;
  }

  static bool canChangePowerLevel({
    required int actorPowerLevel,
    required int targetPowerLevel,
    required int newPowerLevel,
  }) {
    return canManageAdmins(actorPowerLevel) &&
        targetPowerLevel < 100 &&
        actorPowerLevel > targetPowerLevel &&
        newPowerLevel < actorPowerLevel;
  }

  void _ensureOwnPower(Room room, int requiredPower, String action) {
    if (room.ownPowerLevel.level < requiredPower) {
      throw Exception('You do not have permission to $action.');
    }
  }

  Future<void> _ensureCanModerateMember(
    Room room,
    String userId,
    String action,
  ) async {
    final myUserId = _client.userID;
    if (myUserId == userId) {
      throw Exception('You cannot $action yourself.');
    }

    final targetPower = await _getMemberPowerLevel(room, userId);
    if (!canActOnMember(
      actorPowerLevel: room.ownPowerLevel.level,
      targetPowerLevel: targetPower,
    )) {
      throw Exception('You do not have permission to $action this member.');
    }
  }

  Future<void> _ensureCanChangePowerLevel(
    Room room,
    String userId,
    int newPowerLevel,
  ) async {
    final myUserId = _client.userID;
    if (myUserId == userId) {
      throw Exception('You cannot change your own admin role.');
    }

    final targetPower = await _getMemberPowerLevel(room, userId);
    if (!canChangePowerLevel(
      actorPowerLevel: room.ownPowerLevel.level,
      targetPowerLevel: targetPower,
      newPowerLevel: newPowerLevel,
    )) {
      throw Exception('Only owners can change admin roles.');
    }
  }

  Future<int> _getMemberPowerLevel(Room room, String userId) async {
    await room.requestParticipants();
    for (final user in room.getParticipants()) {
      if (user.id == userId) return user.powerLevel.level;
    }

    final powerLevels = room.getState(EventTypes.RoomPowerLevels)?.content;
    final users = powerLevels?['users'];
    if (users is Map && users[userId] is num) {
      return (users[userId] as num).toInt();
    }

    return 0;
  }

  Map<String, MemberRestriction> _activeRestrictionsByUser(Room room) {
    final states = room.states[_memberRestrictionStateType];
    if (states == null) return const {};

    final restrictions = <String, MemberRestriction>{};
    for (final state in states.values) {
      final userId = state.stateKey;
      if (userId == null || state.content['removed'] == true) continue;
      final restriction = MemberRestriction.fromJson(state.content);
      if (!restriction.isExpired) {
        restrictions[userId] = restriction;
      }
    }
    return restrictions;
  }

  MemberRestriction? _restrictionFor(Room room, String userId) {
    final state = room.getState(_memberRestrictionStateType, userId);
    if (state == null || state.content['removed'] == true) return null;
    final restriction = MemberRestriction.fromJson(state.content);
    return restriction.isExpired ? null : restriction;
  }

  Future<void> _recordAdminAction(
    String roomId,
    AdminActionType type, {
    String? targetUser,
    String? targetMessage,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final room = _client.getRoomById(roomId);
      if (room == null) return;

      final now = DateTime.now();
      final action = AdminAction(
        actionId: now.microsecondsSinceEpoch.toString(),
        type: type,
        performedBy: _client.userID ?? '',
        targetUser: targetUser,
        targetMessage: targetMessage,
        timestamp: now,
        metadata: metadata,
      );

      await room.client.setRoomStateWithKey(
        roomId,
        _adminActionStateType,
        action.actionId,
        action.toJson(),
      );
    } catch (e) {
      debugPrint('[GroupService] Failed to record admin action: $e');
    }
  }

  /// Deletes a group/channel permanently
  /// This kicks all members and makes the room inaccessible
  Future<void> deleteGroup(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    debugPrint('[GroupService] Deleting group/channel: $roomId');

    // Get all members
    await room.requestParticipants();
    final participants = room.getParticipants();

    // Kick all members except self
    final myUserId = _client.userID;
    for (final user in participants) {
      if (user.id != myUserId) {
        try {
          await room.kick(user.id);
          debugPrint('[GroupService] Kicked ${user.id}');
        } catch (e) {
          debugPrint('[GroupService] Failed to kick ${user.id}: $e');
        }
      }
    }

    // Leave the room (as admin)
    try {
      await room.leave();
      debugPrint('[GroupService] Admin left the room');
    } catch (e) {
      debugPrint('[GroupService] Failed to leave: $e');
    }

    // Forget the room (removes from local database)
    try {
      await room.forget();
      debugPrint('[GroupService] Room forgotten');
    } catch (e) {
      debugPrint('[GroupService] Failed to forget: $e');
    }

    debugPrint('[GroupService] Group deleted successfully');
  }
}
