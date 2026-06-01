import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../models/group_models.dart';
import '../services/group_service.dart';
import '../services/matrix_service.dart';

/// Provider for managing group state and operations
class GroupProvider extends ChangeNotifier {
  final GroupService _groupService;

  GroupProvider(MatrixService matrixService)
      : _groupService = GroupService(matrixService);

  // Current group being viewed
  String? _currentGroupId;
  String? get currentGroupId => _currentGroupId;

  // Group members cache
  final Map<String, List<GroupMember>> _membersCache = {};

  // Pinned messages cache
  final Map<String, List<PinnedMessage>> _pinnedCache = {};

  // Admin action log cache
  final Map<String, List<AdminAction>> _adminLogCache = {};

  // Loading states
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Creates a new group
  Future<String?> createGroup({
    required String name,
    String? description,
    GroupType type = GroupType.private,
    JoinRule joinRule = JoinRule.invite,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final roomId = await _groupService.createGroup(
        name: name,
        description: description,
        type: type,
        joinRule: joinRule,
      );

      _isLoading = false;
      notifyListeners();
      return roomId;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Updates group settings
  Future<bool> updateGroupSettings(
      String roomId, GroupSettings settings) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _groupService.updateGroupSettings(roomId, settings);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Gets group settings
  Future<GroupSettings?> getGroupSettings(String roomId) async {
    try {
      return await _groupService.getGroupSettings(roomId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MEMBER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets group members (with caching)
  Future<List<GroupMember>> getGroupMembers(String roomId,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _membersCache.containsKey(roomId)) {
      return _membersCache[roomId]!;
    }

    try {
      final members = await _groupService.getGroupMembers(roomId);
      _membersCache[roomId] = members;
      notifyListeners();
      return members;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  /// Adds a member to the group
  Future<bool> addMember(String roomId, String userId) async {
    try {
      await _groupService.addMember(roomId, userId);
      // Invalidate cache
      _membersCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Removes a member from the group
  Future<bool> removeMember(String roomId, String userId,
      {String? reason}) async {
    try {
      await _groupService.removeMember(roomId, userId, reason: reason);
      // Invalidate cache
      _membersCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Bans a member
  Future<bool> banMember(String roomId, String userId, {String? reason}) async {
    try {
      await _groupService.banMember(roomId, userId, reason: reason);
      // Invalidate cache
      _membersCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Unbans a member
  Future<bool> unbanMember(String roomId, String userId) async {
    try {
      await _groupService.unbanMember(roomId, userId);
      // Invalidate cache
      _membersCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Gets banned members
  Future<List<GroupMember>> getBannedMembers(String roomId) async {
    try {
      return await _groupService.getBannedMembers(roomId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP DELETION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Deletes a group permanently (admin only)
  Future<bool> deleteGroup(String roomId) async {
    try {
      await _groupService.deleteGroup(roomId);
      // Invalidate caches
      _membersCache.remove(roomId);
      _pinnedCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADMIN MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Promotes a user to admin
  Future<bool> promoteToAdmin(
    String roomId,
    String userId,
    AdminPermissions permissions,
  ) async {
    try {
      await _groupService.promoteToAdmin(roomId, userId, permissions);
      // Invalidate cache
      _membersCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Demotes an admin to member
  Future<bool> demoteAdmin(String roomId, String userId) async {
    try {
      await _groupService.demoteAdmin(roomId, userId);
      // Invalidate cache
      _membersCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Gets admin permissions for a user
  AdminPermissions? getAdminPermissions(String roomId, String userId) {
    try {
      return _groupService.getAdminPermissions(roomId, userId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Gets all admins
  Future<List<GroupMember>> getAdmins(String roomId) async {
    try {
      return await _groupService.getAdmins(roomId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PINNED MESSAGES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pins a message
  Future<bool> pinMessage(String roomId, String eventId) async {
    try {
      await _groupService.pinMessage(roomId, eventId);
      // Invalidate cache
      _pinnedCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Unpins a message
  Future<bool> unpinMessage(String roomId, String eventId) async {
    try {
      await _groupService.unpinMessage(roomId, eventId);
      // Invalidate cache
      _pinnedCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Gets pinned messages (with caching)
  Future<List<PinnedMessage>> getPinnedMessages(String roomId,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _pinnedCache.containsKey(roomId)) {
      return _pinnedCache[roomId]!;
    }

    try {
      final pinned = await _groupService.getPinnedMessages(roomId);
      _pinnedCache[roomId] = pinned;
      notifyListeners();
      return pinned;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPLIES & MENTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sends a reply to a message
  Future<bool> sendReply(
      String roomId, String text, String replyToEventId) async {
    try {
      await _groupService.sendReply(roomId, text, replyToEventId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Sends a message with mentions
  Future<bool> sendMention(
      String roomId, String text, List<String> mentionedUserIds) async {
    try {
      await _groupService.sendMention(roomId, text, mentionedUserIds);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Gets reply information for a message
  Future<MessageReply?> getReplyInfo(String roomId, String eventId) async {
    try {
      return await _groupService.getReplyInfo(roomId, eventId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> restrictMember(
    String roomId,
    MemberRestriction restriction,
  ) async {
    try {
      await _groupService.restrictMember(roomId, restriction);
      _membersCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeRestriction(String roomId, String userId) async {
    try {
      await _groupService.removeRestriction(roomId, userId);
      _membersCache.remove(roomId);
      _adminLogCache.remove(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<List<AdminAction>> getAdminLog(
    String roomId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _adminLogCache.containsKey(roomId)) {
      return _adminLogCache[roomId]!;
    }

    try {
      final actions = await _groupService.getAdminLog(roomId);
      _adminLogCache[roomId] = actions;
      notifyListeners();
      return actions;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sets the current group being viewed
  void setCurrentGroup(String? roomId) {
    _currentGroupId = roomId;
    notifyListeners();
  }

  /// Clears error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clears all caches
  void clearCaches() {
    _membersCache.clear();
    _pinnedCache.clear();
    _adminLogCache.clear();
    notifyListeners();
  }

  /// Checks if a room is a group
  bool isGroup(Room room) {
    return _groupService.isGroup(room);
  }

  /// Checks if user has permission
  bool hasPermission(Room room, String userId, String action) {
    return _groupService.hasPermission(room, userId, action);
  }

  /// Gets member role badge text
  String getRoleBadge(MemberRole role) {
    switch (role) {
      case MemberRole.owner:
        return 'Owner';
      case MemberRole.admin:
        return 'Admin';
      case MemberRole.moderator:
        return 'Mod';
      case MemberRole.member:
        return '';
      case MemberRole.restricted:
        return 'Restricted';
    }
  }

  /// Gets member role color
  Color getRoleColor(MemberRole role) {
    switch (role) {
      case MemberRole.owner:
        return const Color(0xFFFFD700); // Gold
      case MemberRole.admin:
        return const Color(0xFFA3E635); // Lime green
      case MemberRole.moderator:
        return const Color(0xFF3B82F6); // Blue
      case MemberRole.member:
        return Colors.transparent;
      case MemberRole.restricted:
        return const Color(0xFFEF4444); // Red
    }
  }
}
