import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'matrix_service.dart';

enum XmoPrivacyAudience {
  contacts,
  onlySelected,
  hideSelected,
}

class XmoPrivacySettings {
  final bool accountIsPublic;
  final XmoPrivacyAudience profileAvatarAudience;
  final List<String> profileAvatarUserIds;
  final XmoPrivacyAudience storyAudience;
  final List<String> storyUserIds;

  const XmoPrivacySettings({
    this.accountIsPublic = true,
    this.profileAvatarAudience = XmoPrivacyAudience.contacts,
    this.profileAvatarUserIds = const [],
    this.storyAudience = XmoPrivacyAudience.contacts,
    this.storyUserIds = const [],
  });

  factory XmoPrivacySettings.fromJson(Map<String, dynamic> json) {
    return XmoPrivacySettings(
      accountIsPublic: json['account_is_public'] as bool? ?? true,
      profileAvatarAudience: _audienceFromJson(
        json['profile_avatar_audience'] as String?,
      ),
      profileAvatarUserIds: _stringList(json['profile_avatar_user_ids']),
      storyAudience: _audienceFromJson(json['story_audience'] as String?),
      storyUserIds: _stringList(json['story_user_ids']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account_is_public': accountIsPublic,
      'profile_avatar_audience': profileAvatarAudience.name,
      'profile_avatar_user_ids': profileAvatarUserIds,
      'story_audience': storyAudience.name,
      'story_user_ids': storyUserIds,
    };
  }

  XmoPrivacySettings copyWith({
    bool? accountIsPublic,
    XmoPrivacyAudience? profileAvatarAudience,
    List<String>? profileAvatarUserIds,
    XmoPrivacyAudience? storyAudience,
    List<String>? storyUserIds,
  }) {
    return XmoPrivacySettings(
      accountIsPublic: accountIsPublic ?? this.accountIsPublic,
      profileAvatarAudience:
          profileAvatarAudience ?? this.profileAvatarAudience,
      profileAvatarUserIds: profileAvatarUserIds ?? this.profileAvatarUserIds,
      storyAudience: storyAudience ?? this.storyAudience,
      storyUserIds: storyUserIds ?? this.storyUserIds,
    );
  }

  static XmoPrivacyAudience _audienceFromJson(String? value) {
    return XmoPrivacyAudience.values.firstWhere(
      (audience) => audience.name == value,
      orElse: () => XmoPrivacyAudience.contacts,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().toSet().toList();
  }
}

class PrivacyContact {
  final String userId;
  final String displayName;
  final String? avatarUrl;

  const PrivacyContact({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });
}

class PublicAccountProfile {
  final String userId;
  final String displayName;
  final String? avatarUrl;

  const PublicAccountProfile({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });
}

class PrivacyService {
  static const String privacyAccountDataType = 'xmo.user.privacy_settings';
  static const String profilePrivacyEventType = 'xmo.profile.privacy';
  static const String userDirectoryEventType = 'xmo.user.directory';
  static const String userDirectoryAliasLocalpart = 'xmo-user-directory';
  static const String userDirectoryRoomName = 'XMO User Directory';

  final MatrixService _matrixService;

  PrivacyService(this._matrixService);

  Client get _client => _matrixService.client;

  Future<XmoPrivacySettings> loadSettings() async {
    final myUserId = _client.userID;
    if (myUserId == null) return const XmoPrivacySettings();

    try {
      final data = await _client.getAccountData(
        myUserId,
        privacyAccountDataType,
      );
      return XmoPrivacySettings.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('[PrivacyService] Failed to load privacy settings: $e');
      return const XmoPrivacySettings();
    }
  }

  Future<void> saveSettings(XmoPrivacySettings settings) async {
    final myUserId = _client.userID;
    if (myUserId == null) throw Exception('User not logged in');

    await _client.setAccountData(
      myUserId,
      privacyAccountDataType,
      settings.toJson(),
    );
    await syncPublicAccountDirectory(settings);
    await broadcastProfileAvatarPrivacy(settings);
  }

  Future<void> syncPublicAccountDirectory(
    XmoPrivacySettings settings,
  ) async {
    final myUserId = _client.userID;
    if (myUserId == null) return;

    try {
      final room = await _ensureUserDirectoryRoom();
      String displayName = _matrixService.displayName ?? myUserId;
      String? avatarUrl = _matrixService.avatarUrl;

      try {
        final profile = await _client.getProfileFromUserId(myUserId);
        displayName = profile.displayName ?? displayName;
        avatarUrl = profile.avatarUrl?.toString() ?? avatarUrl;
      } catch (_) {}

      await room.sendEvent({
        'msgtype': userDirectoryEventType,
        'user_id': myUserId,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'public': settings.accountIsPublic,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, type: userDirectoryEventType);
    } catch (e) {
      debugPrint('[PrivacyService] Failed to sync public directory: $e');
    }
  }

  Future<List<PublicAccountProfile>> searchPublicAccounts(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty || !normalizedQuery.startsWith('@')) {
      return const [];
    }

    try {
      final room = await _ensureUserDirectoryRoom();
      final timeline = await room.getTimeline();
      final latestByUserId = <String, Event>{};

      for (final event in timeline.events) {
        if (event.type != userDirectoryEventType || event.redacted) continue;
        final userId = event.content['user_id'] as String?;
        if (userId == null || userId.isEmpty) continue;

        final current = latestByUserId[userId];
        if (current == null ||
            event.originServerTs.isAfter(current.originServerTs)) {
          latestByUserId[userId] = event;
        }
      }

      final results = <PublicAccountProfile>[];
      for (final event in latestByUserId.values) {
        if (event.content['public'] != true) continue;

        final userId = event.content['user_id'] as String;
        final displayName = event.content['display_name'] as String? ?? userId;
        final cleanUserId = MatrixService.cleanName(userId).toLowerCase();
        final matchText = '$userId $cleanUserId'.toLowerCase();
        if (!matchText.contains(normalizedQuery)) continue;

        results.add(
          PublicAccountProfile(
            userId: userId,
            displayName: displayName,
            avatarUrl: event.content['avatar_url'] as String?,
          ),
        );
      }

      results.sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
      return results.take(20).toList();
    } catch (e) {
      debugPrint('[PrivacyService] Failed to search public accounts: $e');
      return const [];
    }
  }

  Future<Room> _ensureUserDirectoryRoom() async {
    final existing = _client.rooms.where(_isUserDirectoryRoom).toList();
    if (existing.isNotEmpty) return existing.first;

    const alias =
        '#$userDirectoryAliasLocalpart:${MatrixService.matrixServerName}';
    try {
      await _client.joinRoom(alias);
      await _client.oneShotSync();
      final joined = _client.rooms.where(_isUserDirectoryRoom).toList();
      if (joined.isNotEmpty) return joined.first;
    } catch (e) {
      debugPrint('[PrivacyService] Could not join directory room: $e');
    }

    try {
      final roomId = await _client.createRoom(
        name: userDirectoryRoomName,
        topic: 'XMO public account directory',
        preset: CreateRoomPreset.publicChat,
        visibility: Visibility.public,
        roomAliasName: userDirectoryAliasLocalpart,
        initialState: [
          StateEvent(
            type: MatrixService.roomTypeStateType,
            stateKey: '',
            content: {'kind': 'directory'},
          ),
        ],
      );
      await _client.oneShotSync();
      return _client.getRoomById(roomId) ?? Room(id: roomId, client: _client);
    } catch (e) {
      if (!e.toString().contains('M_ROOM_IN_USE')) rethrow;
      await _client.joinRoom(alias);
      await _client.oneShotSync();
      final joined = _client.rooms.where(_isUserDirectoryRoom).toList();
      if (joined.isNotEmpty) return joined.first;
      rethrow;
    }
  }

  bool _isUserDirectoryRoom(Room room) {
    final type = room.getState(MatrixService.roomTypeStateType)?.content;
    if (type?['kind'] == 'directory') return true;
    return room.canonicalAlias ==
        '#$userDirectoryAliasLocalpart:${MatrixService.matrixServerName}';
  }

  Future<List<PrivacyContact>> getContacts() async {
    final myUserId = _client.userID;
    final contactsById = <String, PrivacyContact>{};

    for (final room in _client.rooms.where((room) => room.isDirectChat)) {
      final userId =
          _matrixService.getDirectPeerUserId(room) ?? room.directChatMatrixID;
      if (userId == null || userId == myUserId) continue;

      String displayName = userId;
      String? avatarUrl;
      try {
        final profile = await _client.getProfileFromUserId(userId);
        displayName = profile.displayName ?? userId;
        avatarUrl = profile.avatarUrl?.toString();
      } catch (_) {
        final matchingMembers =
            room.getParticipants().where((user) => user.id == userId);
        final member = matchingMembers.isEmpty ? null : matchingMembers.first;
        displayName = member?.displayName ?? userId;
        avatarUrl = member?.avatarUrl?.toString();
      }

      contactsById[userId] = PrivacyContact(
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
    }

    final contacts = contactsById.values.toList()
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    return contacts;
  }

  Future<void> broadcastProfileAvatarPrivacy(
    XmoPrivacySettings settings,
  ) async {
    final myUserId = _client.userID;
    if (myUserId == null) return;

    for (final room in _client.rooms.where((room) => room.isDirectChat)) {
      final viewerId =
          _matrixService.getDirectPeerUserId(room) ?? room.directChatMatrixID;
      if (viewerId == null || viewerId == myUserId) continue;

      try {
        await room.sendEvent({
          'msgtype': profilePrivacyEventType,
          'user_id': myUserId,
          'profile_avatar_visible': allowsUser(
            settings.profileAvatarAudience,
            settings.profileAvatarUserIds,
            viewerId,
          ),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, type: profilePrivacyEventType);
      } catch (e) {
        debugPrint(
          '[PrivacyService] Failed to broadcast profile privacy to ${room.id}: $e',
        );
      }
    }
  }

  static bool allowsUser(
    XmoPrivacyAudience audience,
    List<String> userIds,
    String userId,
  ) {
    switch (audience) {
      case XmoPrivacyAudience.contacts:
        return true;
      case XmoPrivacyAudience.onlySelected:
        return userIds.contains(userId);
      case XmoPrivacyAudience.hideSelected:
        return !userIds.contains(userId);
    }
  }
}
