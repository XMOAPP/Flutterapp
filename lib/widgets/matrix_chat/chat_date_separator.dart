import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';

DateTime localCalendarDay(DateTime timestamp) {
  final local = timestamp.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool isSameLocalCalendarDay(DateTime first, DateTime second) {
  return localCalendarDay(first) == localCalendarDay(second);
}

String formatChatDateLabel(DateTime timestamp, {DateTime? now}) {
  final day = localCalendarDay(timestamp);
  final today = localCalendarDay(now ?? DateTime.now());

  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';

  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${day.day} ${months[day.month - 1]} ${day.year}';
}

class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: formatChatDateLabel(date),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: kDarkGrey.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            formatChatDateLabel(date),
            style: GoogleFonts.inter(
              color: kWhite.withValues(alpha: 0.78),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
