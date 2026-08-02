import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../theme.dart';
import '../../services/matrix_service.dart';
import '../../utils/message_presentation.dart';

/// Reply Preview Widget - Shows when replying to a message
class ReplyPreview extends StatelessWidget {
  final Event replyToEvent;
  final VoidCallback onCancel;

  const ReplyPreview({
    super.key,
    required this.replyToEvent,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final senderName = MatrixService.cleanName(replyToEvent.senderId);
    final messagePreview = _getMessagePreview();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: kDarkerGrey,
        border: Border(
          top: BorderSide(color: kMediumGrey, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: kLimeGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $senderName',
                  style: GoogleFonts.inter(
                    color: kLimeGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  messagePreview,
                  style: GoogleFonts.inter(
                    color: kLightGrey,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: kLightGrey, size: 20),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  String _getMessagePreview() {
    final msgType = replyToEvent.messageType;

    if (msgType == MessageTypes.Image) {
      return '📷 Photo';
    } else if (msgType == MessageTypes.Video) {
      return '🎥 Video';
    } else if (msgType == MessageTypes.Audio) {
      return '🎵 Audio';
    } else if (msgType == MessageTypes.File) {
      return '📎 File';
    }

    return matrixVisibleBody(replyToEvent, fallback: 'Message');
  }
}
