import 'package:matrix/matrix.dart';

import '../utils/message_presentation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GROUP SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

enum GroupType { public, private }

enum JoinRule { open, invite, knock }

class GroupSettings {
  final String name;
  final String? description;
  final String? avatarUrl;
  final GroupType type;
  final JoinRule joinRule;
  final int? memberLimit;
  final bool historyVisibleToNewMembers;
  final String? inviteLink;

  GroupSettings({
    required this.name,
    this.description,
    this.avatarUrl,
    this.type = GroupType.private,
    this.joinRule = JoinRule.invite,
    this.memberLimit,
    this.historyVisibleToNewMembers = true,
    this.inviteLink,
  });

  GroupSettings copyWith({
    String? name,
    String? description,
    String? avatarUrl,
    GroupType? type,
    JoinRule? joinRule,
    int? memberLimit,
    bool? historyVisibleToNewMembers,
    String? inviteLink,
  }) {
    return GroupSettings(
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      type: type ?? this.type,
      joinRule: joinRule ?? this.joinRule,
      memberLimit: memberLimit ?? this.memberLimit,
      historyVisibleToNewMembers:
          historyVisibleToNewMembers ?? this.historyVisibleToNewMembers,
      inviteLink: inviteLink ?? this.inviteLink,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'avatarUrl': avatarUrl,
      'type': type.name,
      'joinRule': joinRule.name,
      'memberLimit': memberLimit,
      'historyVisibleToNewMembers': historyVisibleToNewMembers,
      'inviteLink': inviteLink,
    };
  }

  factory GroupSettings.fromJson(Map<String, dynamic> json) {
    return GroupSettings(
      name: json['name'] as String,
      description: json['description'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      type: GroupType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => GroupType.private,
      ),
      joinRule: JoinRule.values.firstWhere(
        (e) => e.name == json['joinRule'],
        orElse: () => JoinRule.invite,
      ),
      memberLimit: json['memberLimit'] as int?,
      historyVisibleToNewMembers:
          json['historyVisibleToNewMembers'] as bool? ?? true,
      inviteLink: json['inviteLink'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GROUP MEMBER
// ═══════════════════════════════════════════════════════════════════════════

enum MemberRole { owner, admin, moderator, member, restricted }

class GroupMember {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final MemberRole role;
  final int powerLevel;
  final DateTime joinedAt;
  final bool isBanned;
  final MemberRestriction? restriction;

  GroupMember({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    required this.powerLevel,
    required this.joinedAt,
    this.isBanned = false,
    this.restriction,
  });

  /// Determines role from power level
  static MemberRole roleFromPowerLevel(int powerLevel) {
    if (powerLevel >= 100) return MemberRole.owner;
    if (powerLevel >= 75) return MemberRole.admin;
    if (powerLevel >= 50) return MemberRole.moderator;
    if (powerLevel < 0) return MemberRole.restricted;
    return MemberRole.member;
  }

  /// Creates GroupMember from Matrix User
  factory GroupMember.fromUser(User user, Room room) {
    final powerLevel = user.powerLevel.level;
    final role = roleFromPowerLevel(powerLevel);

    return GroupMember(
      userId: user.id,
      displayName: user.displayName ?? user.id,
      avatarUrl: user.avatarUrl?.toString(),
      role: role,
      powerLevel: powerLevel,
      joinedAt: DateTime.now(), // TODO: Get actual join time from room state
      isBanned: false,
    );
  }

  GroupMember copyWith({
    String? userId,
    String? displayName,
    String? avatarUrl,
    MemberRole? role,
    int? powerLevel,
    DateTime? joinedAt,
    bool? isBanned,
    MemberRestriction? restriction,
  }) {
    return GroupMember(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      powerLevel: powerLevel ?? this.powerLevel,
      joinedAt: joinedAt ?? this.joinedAt,
      isBanned: isBanned ?? this.isBanned,
      restriction: restriction ?? this.restriction,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ADMIN PERMISSIONS
// ═══════════════════════════════════════════════════════════════════════════

class AdminPermissions {
  final bool canAddMembers;
  final bool canRemoveMembers;
  final bool canBanMembers;
  final bool canDeleteMessages;
  final bool canPinMessages;
  final bool canEditGroupInfo;
  final bool canManageAdmins;
  final bool canInviteUsers;
  final bool canChangePermissions;

  AdminPermissions({
    this.canAddMembers = false,
    this.canRemoveMembers = false,
    this.canBanMembers = false,
    this.canDeleteMessages = false,
    this.canPinMessages = false,
    this.canEditGroupInfo = false,
    this.canManageAdmins = false,
    this.canInviteUsers = false,
    this.canChangePermissions = false,
  });

  /// Converts permissions to Matrix power level
  int toPowerLevel() {
    if (canManageAdmins) return 100;
    if (canEditGroupInfo || canChangePermissions) return 75;
    if (canAddMembers ||
        canBanMembers ||
        canDeleteMessages ||
        canPinMessages ||
        canInviteUsers) {
      return 50;
    }
    return 0;
  }

  /// Creates permissions from power level
  factory AdminPermissions.fromPowerLevel(int powerLevel) {
    return AdminPermissions(
      canAddMembers: powerLevel >= 50,
      canRemoveMembers: powerLevel >= 50,
      canBanMembers: powerLevel >= 50,
      canDeleteMessages: powerLevel >= 50,
      canPinMessages: powerLevel >= 50,
      canEditGroupInfo: powerLevel >= 75,
      canManageAdmins: powerLevel >= 100,
      canInviteUsers: powerLevel >= 50,
      canChangePermissions: powerLevel >= 75,
    );
  }

  /// Preset: Full admin (power level 100)
  factory AdminPermissions.fullAdmin() {
    return AdminPermissions(
      canAddMembers: true,
      canRemoveMembers: true,
      canBanMembers: true,
      canDeleteMessages: true,
      canPinMessages: true,
      canEditGroupInfo: true,
      canManageAdmins: true,
      canInviteUsers: true,
      canChangePermissions: true,
    );
  }

  /// Preset: Moderator (power level 50)
  factory AdminPermissions.moderator() {
    return AdminPermissions(
      canAddMembers: true,
      canRemoveMembers: true,
      canBanMembers: true,
      canDeleteMessages: true,
      canPinMessages: true,
      canInviteUsers: true,
    );
  }

  AdminPermissions copyWith({
    bool? canAddMembers,
    bool? canRemoveMembers,
    bool? canBanMembers,
    bool? canDeleteMessages,
    bool? canPinMessages,
    bool? canEditGroupInfo,
    bool? canManageAdmins,
    bool? canInviteUsers,
    bool? canChangePermissions,
  }) {
    return AdminPermissions(
      canAddMembers: canAddMembers ?? this.canAddMembers,
      canRemoveMembers: canRemoveMembers ?? this.canRemoveMembers,
      canBanMembers: canBanMembers ?? this.canBanMembers,
      canDeleteMessages: canDeleteMessages ?? this.canDeleteMessages,
      canPinMessages: canPinMessages ?? this.canPinMessages,
      canEditGroupInfo: canEditGroupInfo ?? this.canEditGroupInfo,
      canManageAdmins: canManageAdmins ?? this.canManageAdmins,
      canInviteUsers: canInviteUsers ?? this.canInviteUsers,
      canChangePermissions: canChangePermissions ?? this.canChangePermissions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'canAddMembers': canAddMembers,
      'canRemoveMembers': canRemoveMembers,
      'canBanMembers': canBanMembers,
      'canDeleteMessages': canDeleteMessages,
      'canPinMessages': canPinMessages,
      'canEditGroupInfo': canEditGroupInfo,
      'canManageAdmins': canManageAdmins,
      'canInviteUsers': canInviteUsers,
      'canChangePermissions': canChangePermissions,
    };
  }

  factory AdminPermissions.fromJson(Map<String, dynamic> json) {
    return AdminPermissions(
      canAddMembers: json['canAddMembers'] as bool? ?? false,
      canRemoveMembers: json['canRemoveMembers'] as bool? ?? false,
      canBanMembers: json['canBanMembers'] as bool? ?? false,
      canDeleteMessages: json['canDeleteMessages'] as bool? ?? false,
      canPinMessages: json['canPinMessages'] as bool? ?? false,
      canEditGroupInfo: json['canEditGroupInfo'] as bool? ?? false,
      canManageAdmins: json['canManageAdmins'] as bool? ?? false,
      canInviteUsers: json['canInviteUsers'] as bool? ?? false,
      canChangePermissions: json['canChangePermissions'] as bool? ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MEMBER RESTRICTION
// ═══════════════════════════════════════════════════════════════════════════

enum RestrictionType {
  readOnly, // Can't send messages
  noMedia, // Can't send files/images
  noLinks, // Can't send URLs
  noStickers, // Can't send stickers
  fullBan // Completely banned
}

class MemberRestriction {
  final String userId;
  final RestrictionType type;
  final DateTime? expiresAt;
  final String? reason;
  final String restrictedBy;
  final DateTime restrictedAt;

  MemberRestriction({
    required this.userId,
    required this.type,
    this.expiresAt,
    this.reason,
    required this.restrictedBy,
    required this.restrictedAt,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isPermanent => expiresAt == null;

  MemberRestriction copyWith({
    String? userId,
    RestrictionType? type,
    DateTime? expiresAt,
    String? reason,
    String? restrictedBy,
    DateTime? restrictedAt,
  }) {
    return MemberRestriction(
      userId: userId ?? this.userId,
      type: type ?? this.type,
      expiresAt: expiresAt ?? this.expiresAt,
      reason: reason ?? this.reason,
      restrictedBy: restrictedBy ?? this.restrictedBy,
      restrictedAt: restrictedAt ?? this.restrictedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'type': type.name,
      'expiresAt': expiresAt?.toIso8601String(),
      'reason': reason,
      'restrictedBy': restrictedBy,
      'restrictedAt': restrictedAt.toIso8601String(),
    };
  }

  factory MemberRestriction.fromJson(Map<String, dynamic> json) {
    return MemberRestriction(
      userId: json['userId'] as String,
      type: RestrictionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RestrictionType.readOnly,
      ),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      reason: json['reason'] as String?,
      restrictedBy: json['restrictedBy'] as String,
      restrictedAt: DateTime.parse(json['restrictedAt'] as String),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PINNED MESSAGE
// ═══════════════════════════════════════════════════════════════════════════

class PinnedMessage {
  final String eventId;
  final String content;
  final String senderId;
  final String senderName;
  final DateTime pinnedAt;
  final String? pinnedBy;
  final DateTime originalTimestamp;

  PinnedMessage({
    required this.eventId,
    required this.content,
    required this.senderId,
    required this.senderName,
    required this.pinnedAt,
    this.pinnedBy,
    required this.originalTimestamp,
  });

  factory PinnedMessage.fromEvent(Event event, {String? pinnedBy}) {
    return PinnedMessage(
      eventId: event.eventId,
      content: matrixVisibleBody(event),
      senderId: event.senderId,
      senderName:
          event.senderFromMemoryOrFallback.displayName ?? event.senderId,
      pinnedAt: DateTime.now(),
      pinnedBy: pinnedBy,
      originalTimestamp: event.originServerTs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'content': content,
      'senderId': senderId,
      'senderName': senderName,
      'pinnedAt': pinnedAt.toIso8601String(),
      'pinnedBy': pinnedBy,
      'originalTimestamp': originalTimestamp.toIso8601String(),
    };
  }

  factory PinnedMessage.fromJson(Map<String, dynamic> json) {
    return PinnedMessage(
      eventId: json['eventId'] as String,
      content: json['content'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      pinnedAt: DateTime.parse(json['pinnedAt'] as String),
      pinnedBy: json['pinnedBy'] as String?,
      originalTimestamp: DateTime.parse(json['originalTimestamp'] as String),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGE REPLY
// ═══════════════════════════════════════════════════════════════════════════

enum AdminActionType {
  memberAdded,
  memberRemoved,
  memberBanned,
  memberUnbanned,
  memberPromoted,
  memberDemoted,
  memberRestricted,
  memberRestrictionRemoved,
  messagePinned,
  messageUnpinned,
  settingsChanged,
}

class AdminAction {
  final String actionId;
  final AdminActionType type;
  final String performedBy;
  final String? targetUser;
  final String? targetMessage;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const AdminAction({
    required this.actionId,
    required this.type,
    required this.performedBy,
    this.targetUser,
    this.targetMessage,
    required this.timestamp,
    this.metadata = const {},
  });

  String get label {
    switch (type) {
      case AdminActionType.memberAdded:
        return 'Invited member';
      case AdminActionType.memberRemoved:
        return 'Removed member';
      case AdminActionType.memberBanned:
        return 'Banned member';
      case AdminActionType.memberUnbanned:
        return 'Unbanned member';
      case AdminActionType.memberPromoted:
        return 'Promoted member';
      case AdminActionType.memberDemoted:
        return 'Demoted admin';
      case AdminActionType.memberRestricted:
        return 'Restricted member';
      case AdminActionType.memberRestrictionRemoved:
        return 'Removed restriction';
      case AdminActionType.messagePinned:
        return 'Pinned message';
      case AdminActionType.messageUnpinned:
        return 'Unpinned message';
      case AdminActionType.settingsChanged:
        return 'Changed settings';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'action_id': actionId,
      'type': type.name,
      'performed_by': performedBy,
      if (targetUser != null) 'target_user': targetUser,
      if (targetMessage != null) 'target_message': targetMessage,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory AdminAction.fromJson(Map<dynamic, dynamic> json) {
    return AdminAction(
      actionId: json['action_id'] as String? ?? '',
      type: AdminActionType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => AdminActionType.settingsChanged,
      ),
      performedBy: json['performed_by'] as String? ?? '',
      targetUser: json['target_user'] as String?,
      targetMessage: json['target_message'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      metadata: _metadataFromJson(json['metadata']),
    );
  }

  static Map<String, dynamic> _metadataFromJson(dynamic value) {
    if (value is! Map) return const {};
    return Map<String, dynamic>.from(value);
  }
}

class MessageReply {
  final String eventId;
  final String senderId;
  final String senderName;
  final String messagePreview;
  final DateTime timestamp;

  MessageReply({
    required this.eventId,
    required this.senderId,
    required this.senderName,
    required this.messagePreview,
    required this.timestamp,
  });

  factory MessageReply.fromEvent(Event event) {
    final preview = matrixVisibleBody(event);
    return MessageReply(
      eventId: event.eventId,
      senderId: event.senderId,
      senderName:
          event.senderFromMemoryOrFallback.displayName ?? event.senderId,
      messagePreview:
          preview.length > 100 ? '${preview.substring(0, 100)}...' : preview,
      timestamp: event.originServerTs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'senderId': senderId,
      'senderName': senderName,
      'messagePreview': messagePreview,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MessageReply.fromJson(Map<String, dynamic> json) {
    return MessageReply(
      eventId: json['eventId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      messagePreview: json['messagePreview'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
