import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/widgets/matrix_chat/chat_date_separator.dart';

void main() {
  group('formatChatDateLabel', () {
    final now = DateTime(2026, 7, 21, 14, 30);

    test('labels the current local day as Today', () {
      expect(formatChatDateLabel(DateTime(2026, 7, 21, 1), now: now), 'Today');
    });

    test('labels the previous local day as Yesterday', () {
      expect(
        formatChatDateLabel(DateTime(2026, 7, 20, 23, 59), now: now),
        'Yesterday',
      );
    });

    test('uses an explicit date for older messages', () {
      expect(
        formatChatDateLabel(DateTime(2025, 12, 3), now: now),
        '3 December 2025',
      );
    });
  });

  test('calendar-day comparison ignores the time of day', () {
    expect(
      isSameLocalCalendarDay(
        DateTime(2026, 7, 21, 0, 1),
        DateTime(2026, 7, 21, 23, 59),
      ),
      isTrue,
    );
    expect(
      isSameLocalCalendarDay(
        DateTime(2026, 7, 20, 23, 59),
        DateTime(2026, 7, 21, 0, 1),
      ),
      isFalse,
    );
  });
}
