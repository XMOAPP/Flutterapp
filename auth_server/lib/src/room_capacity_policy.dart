/// Shared limits for XMO's room-capacity checks.
abstract final class RoomCapacityPolicy {
  static const int groupMemberLimit = 50;
  static const int channelMemberLimit = 100;

  static int limitForRoomType(String roomType) {
    return roomType == 'channel' ? channelMemberLimit : groupMemberLimit;
  }

  static String fullMessage(String roomType) {
    final limit = limitForRoomType(roomType);
    final unit = roomType == 'channel' ? 'subscribers' : 'members';
    return 'This $roomType is full ($limit $unit maximum).';
  }

  static bool hasSpace({
    required String roomType,
    required int joinedMemberCount,
    required bool alreadyJoined,
  }) {
    return alreadyJoined || joinedMemberCount < limitForRoomType(roomType);
  }
}
