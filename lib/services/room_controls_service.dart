import 'package:matrix/matrix.dart';

enum XmoJoinMode {
  public,
  invite,
  request,
}

enum XmoRoomPermission {
  sendMessages,
  sendMedia,
  startCalls,
  sendPolls,
  sendStickers,
}

class XmoRoomPermissions {
  final int sendMessages;
  final int sendMedia;
  final int startCalls;
  final int sendPolls;
  final int sendStickers;

  const XmoRoomPermissions({
    this.sendMessages = 0,
    this.sendMedia = 0,
    this.startCalls = 0,
    this.sendPolls = 0,
    this.sendStickers = 0,
  });

  factory XmoRoomPermissions.fromRoom(Room room) {
    final content =
        room.getState(RoomControlsService.permissionsStateType)?.content;
    return XmoRoomPermissions(
      sendMessages: RoomControlsService._intFromContent(
        content,
        RoomControlsService.sendMessagesKey,
        fallback: RoomControlsService._eventsDefaultPower(room),
      ),
      sendMedia: RoomControlsService._intFromContent(
        content,
        RoomControlsService.sendMediaKey,
        fallback: RoomControlsService._eventsDefaultPower(room),
      ),
      startCalls: RoomControlsService._intFromContent(
        content,
        RoomControlsService.startCallsKey,
        fallback: 0,
      ),
      sendPolls: RoomControlsService._intFromContent(
        content,
        RoomControlsService.sendPollsKey,
        fallback: RoomControlsService._eventsDefaultPower(room),
      ),
      sendStickers: RoomControlsService._intFromContent(
        content,
        RoomControlsService.sendStickersKey,
        fallback: RoomControlsService._eventsDefaultPower(room),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      RoomControlsService.sendMessagesKey: sendMessages,
      RoomControlsService.sendMediaKey: sendMedia,
      RoomControlsService.startCallsKey: startCalls,
      RoomControlsService.sendPollsKey: sendPolls,
      RoomControlsService.sendStickersKey: sendStickers,
    };
  }
}

class RoomControlsService {
  static const slowModeStateType = 'xmo.room.slow_mode';
  static const permissionsStateType = 'xmo.room.permissions';

  static const sendMessagesKey = 'send_messages';
  static const sendMediaKey = 'send_media';
  static const startCallsKey = 'start_calls';
  static const sendPollsKey = 'send_polls';
  static const sendStickersKey = 'send_stickers';

  static XmoJoinMode joinModeFor(Room room) {
    final content = room.getState(EventTypes.RoomJoinRules)?.content;
    final raw = content?['join_rule']?.toString();
    switch (raw) {
      case 'public':
        return XmoJoinMode.public;
      case 'knock':
        return XmoJoinMode.request;
      case 'invite':
      default:
        return XmoJoinMode.invite;
    }
  }

  static String joinRuleFor(XmoJoinMode mode) {
    switch (mode) {
      case XmoJoinMode.public:
        return 'public';
      case XmoJoinMode.request:
        return 'knock';
      case XmoJoinMode.invite:
        return 'invite';
    }
  }

  static Future<void> setJoinMode(Room room, XmoJoinMode mode) async {
    await room.client.setRoomStateWithKey(
      room.id,
      EventTypes.RoomJoinRules,
      '',
      {'join_rule': joinRuleFor(mode)},
    );
  }

  static int slowModeSecondsFor(Room room) {
    final content = room.getState(slowModeStateType)?.content;
    final enabled = content?['enabled'];
    if (enabled == false || enabled?.toString() == 'false') return 0;
    return _intFromContent(content, 'seconds', fallback: 0)
        .clamp(0, 86400)
        .toInt();
  }

  static Future<void> setSlowModeSeconds(Room room, int seconds) async {
    final clampedSeconds = seconds.clamp(0, 86400);
    await room.client.setRoomStateWithKey(
      room.id,
      slowModeStateType,
      '',
      {
        'enabled': clampedSeconds > 0,
        'seconds': clampedSeconds,
      },
    );
  }

  static Future<void> setPermissions(
    Room room,
    XmoRoomPermissions permissions,
  ) async {
    await room.client.setRoomStateWithKey(
      room.id,
      permissionsStateType,
      '',
      permissions.toJson(),
    );
  }

  static bool canPerform(
    Room room,
    String? userId,
    XmoRoomPermission permission,
  ) {
    if (userId == null || userId.isEmpty) return false;
    final requiredPower = requiredPowerFor(room, permission);
    return powerLevelFor(room, userId) >= requiredPower;
  }

  static int requiredPowerFor(Room room, XmoRoomPermission permission) {
    final permissions = XmoRoomPermissions.fromRoom(room);
    switch (permission) {
      case XmoRoomPermission.sendMessages:
        return permissions.sendMessages;
      case XmoRoomPermission.sendMedia:
        return permissions.sendMedia;
      case XmoRoomPermission.startCalls:
        return permissions.startCalls;
      case XmoRoomPermission.sendPolls:
        return permissions.sendPolls;
      case XmoRoomPermission.sendStickers:
        return permissions.sendStickers;
    }
  }

  static bool canBypassSlowMode(Room room, String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return powerLevelFor(room, userId) >= 50;
  }

  static Duration slowModeRemaining(
    Room room,
    String? userId,
    Iterable<Event> events,
  ) {
    final seconds = slowModeSecondsFor(room);
    if (seconds <= 0 || canBypassSlowMode(room, userId)) {
      return Duration.zero;
    }
    final lastSent = events
        .where((event) =>
            event.senderId == userId &&
            event.type == EventTypes.Message &&
            event.messageType != MessageTypes.BadEncrypted)
        .map((event) => event.originServerTs)
        .fold<DateTime?>(null, (latest, current) {
      if (latest == null || current.isAfter(latest)) return current;
      return latest;
    });
    if (lastSent == null) return Duration.zero;
    final nextAllowedAt = lastSent.add(Duration(seconds: seconds));
    final remaining = nextAllowedAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static int powerLevelFor(Room room, String userId) {
    for (final user in room.getParticipants()) {
      if (user.id == userId) return user.powerLevel;
    }
    final content = room.getState(EventTypes.RoomPowerLevels)?.content;
    final users = content?['users'];
    if (users is Map && users[userId] is num) {
      return (users[userId] as num).toInt();
    }
    return _intFromContent(content, 'users_default', fallback: 0);
  }

  static String roleLabelForPower(int power) {
    if (power >= 100) return 'Owner only';
    if (power >= 75) return 'Admins only';
    if (power >= 50) return 'Moderators and above';
    return 'All members';
  }

  static int _eventsDefaultPower(Room room) {
    return _intFromContent(
      room.getState(EventTypes.RoomPowerLevels)?.content,
      'events_default',
      fallback: 0,
    );
  }

  static int _intFromContent(
    Map<dynamic, dynamic>? content,
    String key, {
    required int fallback,
  }) {
    final value = content?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}
