import 'package:test/test.dart';
import 'package:xmo_auth_server/src/room_capacity_policy.dart';

void main() {
  group('RoomCapacityPolicy', () {
    test('allows the 50th group member but rejects the 51st', () {
      expect(
        RoomCapacityPolicy.hasSpace(
          roomType: 'group',
          joinedMemberCount: 49,
          alreadyJoined: false,
        ),
        isTrue,
      );
      expect(
        RoomCapacityPolicy.hasSpace(
          roomType: 'group',
          joinedMemberCount: 50,
          alreadyJoined: false,
        ),
        isFalse,
      );
    });

    test('allows the 100th channel subscriber but rejects the 101st', () {
      expect(
        RoomCapacityPolicy.hasSpace(
          roomType: 'channel',
          joinedMemberCount: 99,
          alreadyJoined: false,
        ),
        isTrue,
      );
      expect(
        RoomCapacityPolicy.hasSpace(
          roomType: 'channel',
          joinedMemberCount: 100,
          alreadyJoined: false,
        ),
        isFalse,
      );
    });

    test('does not block an already joined user', () {
      expect(
        RoomCapacityPolicy.hasSpace(
          roomType: 'group',
          joinedMemberCount: 50,
          alreadyJoined: true,
        ),
        isTrue,
      );
    });
  });
}
