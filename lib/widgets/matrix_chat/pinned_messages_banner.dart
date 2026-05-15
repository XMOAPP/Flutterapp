import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../theme.dart';
import '../../services/matrix_service.dart';

/// Pinned Messages Banner - Shows at top of chat when messages are pinned
class PinnedMessagesBanner extends StatelessWidget {
  final List<Event> pinnedEvents;
  final VoidCallback onTap;

  const PinnedMessagesBanner({
    super.key,
    required this.pinnedEvents,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (pinnedEvents.isEmpty) return const SizedBox.shrink();

    final firstPinned = pinnedEvents.first;
    final senderName = MatrixService.cleanName(firstPinned.senderId);
    final messagePreview = _getMessagePreview(firstPinned);
    final count = pinnedEvents.length;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: const BoxDecoration(color: kDarkerGrey),
        child: Row(
          children: [
            const Icon(
              Icons.push_pin,
              color: kLimeGreen,
              size: 16,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count > 1 ? '$count Pinned Messages' : 'Pinned Message',
                    style: GoogleFonts.inter(
                      color: kLimeGreen,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$senderName: $messagePreview',
                    style: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: kLightGrey,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _getMessagePreview(Event event) {
    final msgType = event.messageType;

    if (msgType == MessageTypes.Image) {
      return 'Photo';
    } else if (msgType == MessageTypes.Video) {
      return 'Video';
    } else if (msgType == MessageTypes.Audio) {
      return 'Audio';
    } else if (msgType == MessageTypes.File) {
      return 'File';
    }

    return event.body;
  }
}
