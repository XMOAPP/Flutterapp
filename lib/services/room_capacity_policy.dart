import 'package:matrix/matrix.dart';

/// XMO's joined-member limits. The Synapse module is the final authority;
/// these helpers provide immediate feedback before an administrator sends an
/// invite or approves a join request.
abstract final class RoomCapacityPolicy {
  static const int groupMemberLimit = 50;
  static const int channelMemberLimit = 100;

  static int joinedMemberCount(Room room) {
    return room.summary.mJoinedMemberCount ??
        room
            .getParticipants()
            .where((user) => user.membership == Membership.join)
            .length;
  }

  static void ensureGroupHasSpace(Room room) {
    _ensureHasSpace(
      joinedMemberCount(room),
      groupMemberLimit,
      label: 'group',
      unit: 'members',
    );
  }

  static void ensureChannelHasSpace(Room room) {
    _ensureHasSpace(
      joinedMemberCount(room),
      channelMemberLimit,
      label: 'channel',
      unit: 'subscribers',
    );
  }

  static String groupCountLabel(int count) =>
      '$count / $groupMemberLimit members';

  static String channelCountLabel(int count) =>
      '$count / $channelMemberLimit subscribers';

  static void _ensureHasSpace(
    int currentCount,
    int limit, {
    required String label,
    required String unit,
  }) {
    if (currentCount >= limit) {
      throw StateError('This $label is full ($limit $unit maximum).');
    }
  }
}
