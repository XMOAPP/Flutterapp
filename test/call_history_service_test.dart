import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/call_history_service.dart';

void main() {
  CallHistoryEntry entry({
    CallHistoryKind kind = CallHistoryKind.direct,
    CallHistoryDirection direction = CallHistoryDirection.incoming,
    CallHistoryStatus status = CallHistoryStatus.answered,
    bool video = false,
    Duration? duration,
  }) {
    return CallHistoryEntry(
      id: 'call-1',
      ownerUserId: '@alice:example.org',
      roomId: '!room:example.org',
      roomName: 'Alice',
      kind: kind,
      direction: direction,
      status: status,
      video: video,
      timestamp: DateTime.utc(2026, 6, 27, 12),
      duration: duration,
    );
  }

  test('call history entries round-trip through persisted JSON', () {
    final source = entry(
      kind: CallHistoryKind.group,
      direction: CallHistoryDirection.outgoing,
      status: CallHistoryStatus.ended,
      video: true,
      duration: const Duration(minutes: 2, seconds: 5),
    );
    final restored = CallHistoryEntry.fromJson(source.toJson());

    expect(restored.ownerUserId, source.ownerUserId);
    expect(restored.kind, CallHistoryKind.group);
    expect(restored.direction, CallHistoryDirection.outgoing);
    expect(restored.status, CallHistoryStatus.ended);
    expect(restored.video, isTrue);
    expect(restored.duration, const Duration(minutes: 2, seconds: 5));
  });

  test(
    'call subtitles distinguish missed, rejected, direct, and group calls',
    () {
      expect(
        entry(status: CallHistoryStatus.missed).subtitle,
        'Missed voice call',
      );
      expect(
        entry(status: CallHistoryStatus.rejected).subtitle,
        'Rejected voice call',
      );
      expect(
        entry(
          kind: CallHistoryKind.group,
          direction: CallHistoryDirection.outgoing,
          status: CallHistoryStatus.rejected,
          video: true,
        ).subtitle,
        'Declined group video call',
      );
    },
  );

  test('call subtitles include positive duration', () {
    expect(
      entry(duration: const Duration(minutes: 2, seconds: 5)).subtitle,
      contains('02:05'),
    );
    expect(entry(duration: Duration.zero).subtitle, isNot(contains('00:00')));
  });
}
