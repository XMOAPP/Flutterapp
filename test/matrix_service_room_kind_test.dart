import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/matrix_service.dart';

void main() {
  group('MatrixService room kind classification', () {
    test('explicit channel marker wins', () {
      final kind = MatrixService.classifyRoomKind(
        typeContent: {'is_channel': true, 'is_group': false},
        powerLevelsContent: {'events_default': 0, 'users_default': 0},
        isDirectChat: false,
        useGroupFallback: true,
      );

      expect(kind, XmoRoomKind.channel);
    });

    test('explicit direct marker wins over fallback heuristics', () {
      final kind = MatrixService.classifyRoomKind(
        typeContent: {'is_direct': true, 'kind': 'direct'},
        powerLevelsContent: {'events_default': 50, 'users_default': 0},
        isDirectChat: false,
        useGroupFallback: true,
      );

      expect(kind, XmoRoomKind.direct);
    });

    test('explicit group marker wins over channel-like power levels', () {
      final kind = MatrixService.classifyRoomKind(
        typeContent: {'is_group': true, 'is_channel': false},
        powerLevelsContent: {'events_default': 50, 'users_default': 0},
        isDirectChat: false,
        useGroupFallback: true,
      );

      expect(kind, XmoRoomKind.group);
    });

    test('channel power level fingerprint marks a channel', () {
      final kind = MatrixService.classifyRoomKind(
        powerLevelsContent: {'events_default': 50, 'users_default': 0},
        isDirectChat: false,
      );

      expect(kind, XmoRoomKind.channel);
      expect(
        MatrixService.powerLevelsMarkChannel({
          'events_default': 75,
          'users_default': 0,
        }),
        isTrue,
      );
    });

    test('normal group power levels do not mark a channel', () {
      expect(
        MatrixService.powerLevelsMarkChannel({
          'events_default': 0,
          'users_default': 0,
        }),
        isFalse,
      );
    });

    test('direct rooms stay direct unless explicitly typed', () {
      final kind = MatrixService.classifyRoomKind(
        isDirectChat: true,
        useGroupFallback: true,
      );

      expect(kind, XmoRoomKind.direct);
    });

    test('non-direct unknown rooms can fall back to group', () {
      final kind = MatrixService.classifyRoomKind(
        isDirectChat: false,
        useGroupFallback: true,
      );

      expect(kind, XmoRoomKind.group);
    });

    test('non-direct unknown rooms can remain unknown without fallback', () {
      final kind = MatrixService.classifyRoomKind(isDirectChat: false);

      expect(kind, isNull);
    });
  });
}
