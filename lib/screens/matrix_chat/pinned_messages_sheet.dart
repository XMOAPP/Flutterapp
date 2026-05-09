import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../theme.dart';
import '../../services/matrix_service.dart';

void showPinnedMessagesSheet({
  required BuildContext context,
  required List<Event> pinnedEvents,
  bool canUnpin = false,
  Future<void> Function(Event event)? onUnpin,
}) {
  if (pinnedEvents.isEmpty) return;

  showModalBottomSheet(
    context: context,
    backgroundColor: kDarkerGrey,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.push_pin, color: kLimeGreen),
                const SizedBox(width: 12),
                Text(
                  'Pinned Messages',
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: kMediumGrey, height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: pinnedEvents.length,
              itemBuilder: (_, i) => _PinnedMessageTile(
                event: pinnedEvents[i],
                canUnpin: canUnpin,
                onUnpin: onUnpin,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PinnedMessageTile extends StatelessWidget {
  final Event event;
  final bool canUnpin;
  final Future<void> Function(Event event)? onUnpin;

  const _PinnedMessageTile({
    required this.event,
    required this.canUnpin,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final senderName = MatrixService.cleanName(event.senderId);
    final time = _formatTime(event.originServerTs);

    return ListTile(
      leading: const Icon(Icons.push_pin, color: kLimeGreen, size: 20),
      title: Text(
        senderName,
        style: GoogleFonts.inter(
          color: kLimeGreen,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        event.body,
        style: GoogleFonts.inter(color: kWhite, fontSize: 14),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: canUnpin && onUnpin != null
          ? IconButton(
              icon: const Icon(Icons.push_pin_outlined, color: kLightGrey),
              tooltip: 'Unpin message',
              onPressed: () async {
                Navigator.pop(context);
                await onUnpin!(event);
              },
            )
          : Text(
              time,
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
            ),
      onTap: () {
        Navigator.pop(context);
      },
    );
  }
}

String _formatTime(DateTime dt) {
  final hour = dt.hour;
  final minute = dt.minute.toString().padLeft(2, '0');

  if (hour == 0) {
    return '12:$minute AM';
  } else if (hour < 12) {
    return '$hour:$minute AM';
  } else if (hour == 12) {
    return '12:$minute PM';
  } else {
    return '${hour - 12}:$minute PM';
  }
}
