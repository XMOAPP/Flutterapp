import 'package:matrix/matrix.dart';

/// Channel-specific models for broadcast channels

/// Channel subscriber information
class ChannelSubscriber {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final DateTime joinedAt;
  final bool isBanned;
  final bool isAdmin;
  final int powerLevel;

  ChannelSubscriber({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.joinedAt,
    this.isBanned = false,
    this.isAdmin = false,
    required this.powerLevel,
  });

  factory ChannelSubscriber.fromUser(User user, Room room) {
    return ChannelSubscriber(
      userId: user.id,
      displayName: user.displayName ?? user.id,
      avatarUrl: user.avatarUrl?.toString(),
      joinedAt: DateTime.now(), // Matrix doesn't store join time easily
      isBanned: false,
      isAdmin: user.powerLevel >= PowerLevel.moderator,
      powerLevel: user.powerLevel.level,
    );
  }
}

/// Channel admin with specific permissions
class ChannelAdmin {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final ChannelAdminPermissions permissions;
  final DateTime promotedAt;
  final int powerLevel;

  ChannelAdmin({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.permissions,
    required this.promotedAt,
    required this.powerLevel,
  });

  factory ChannelAdmin.fromUser(User user) {
    return ChannelAdmin(
      userId: user.id,
      displayName: user.displayName ?? user.id,
      avatarUrl: user.avatarUrl?.toString(),
      permissions:
          ChannelAdminPermissions.fromPowerLevel(user.powerLevel.level),
      promotedAt: DateTime.now(),
      powerLevel: user.powerLevel.level,
    );
  }
}

/// Channel admin permissions
class ChannelAdminPermissions {
  final bool canPostMessages;
  final bool canEditChannelInfo;
  final bool canDeleteMessages;
  final bool canAddAdmins;
  final bool canBanSubscribers;
  final bool canPinMessages;
  final bool canManageInviteLinks;
  final bool canViewStatistics;

  ChannelAdminPermissions({
    this.canPostMessages = false,
    this.canEditChannelInfo = false,
    this.canDeleteMessages = false,
    this.canAddAdmins = false,
    this.canBanSubscribers = false,
    this.canPinMessages = false,
    this.canManageInviteLinks = false,
    this.canViewStatistics = false,
  });

  factory ChannelAdminPermissions.fromPowerLevel(int powerLevel) {
    if (powerLevel >= 100) {
      // Owner - all permissions
      return ChannelAdminPermissions(
        canPostMessages: true,
        canEditChannelInfo: true,
        canDeleteMessages: true,
        canAddAdmins: true,
        canBanSubscribers: true,
        canPinMessages: true,
        canManageInviteLinks: true,
        canViewStatistics: true,
      );
    } else if (powerLevel >= 75) {
      // Admin - most permissions
      return ChannelAdminPermissions(
        canPostMessages: true,
        canEditChannelInfo: true,
        canDeleteMessages: true,
        canAddAdmins: false,
        canBanSubscribers: true,
        canPinMessages: true,
        canManageInviteLinks: true,
        canViewStatistics: true,
      );
    } else if (powerLevel >= 50) {
      // Moderator - basic permissions
      return ChannelAdminPermissions(
        canPostMessages: true,
        canEditChannelInfo: false,
        canDeleteMessages: true,
        canAddAdmins: false,
        canBanSubscribers: true,
        canPinMessages: true,
        canManageInviteLinks: false,
        canViewStatistics: false,
      );
    }
    return ChannelAdminPermissions();
  }

  int toPowerLevel() {
    if (canAddAdmins) return 100;
    if (canEditChannelInfo) return 75;
    if (canPostMessages) return 50;
    return 0;
  }
}

/// Channel settings
class ChannelSettings {
  final String name;
  final String? description;
  final String? avatarUrl;
  final bool isPublic;
  final bool signMessages; // Show admin name on posts
  final String? linkedDiscussionGroupId;
  final bool allowComments;

  ChannelSettings({
    required this.name,
    this.description,
    this.avatarUrl,
    this.isPublic = true,
    this.signMessages = true,
    this.linkedDiscussionGroupId,
    this.allowComments = false,
  });
}

/// Channel statistics
class ChannelStatistics {
  final int totalSubscribers;
  final int totalPosts;
  final int postsLast24h;
  final int postsLast7days;
  final int averageViews;
  final DateTime createdAt;
  final List<DailyStats> growthData;

  ChannelStatistics({
    required this.totalSubscribers,
    required this.totalPosts,
    required this.postsLast24h,
    required this.postsLast7days,
    required this.averageViews,
    required this.createdAt,
    this.growthData = const [],
  });
}

/// Daily statistics for charts
class DailyStats {
  final DateTime date;
  final int subscribers;
  final int posts;
  final int views;

  DailyStats({
    required this.date,
    required this.subscribers,
    required this.posts,
    required this.views,
  });
}

/// Post statistics
class PostStatistics {
  final String eventId;
  final int views;
  final int forwards;
  final DateTime postedAt;
  final String postedBy;

  PostStatistics({
    required this.eventId,
    required this.views,
    required this.forwards,
    required this.postedAt,
    required this.postedBy,
  });
}

/// Channel invite link
class ChannelInviteLink {
  final String linkId;
  final String url;
  final String channelId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int usedCount;
  final String createdBy;
  final bool isActive;

  ChannelInviteLink({
    required this.linkId,
    required this.url,
    required this.channelId,
    required this.createdAt,
    this.expiresAt,
    this.usedCount = 0,
    required this.createdBy,
    this.isActive = true,
  });
}
