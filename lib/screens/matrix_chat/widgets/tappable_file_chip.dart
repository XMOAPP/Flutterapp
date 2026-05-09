import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../../theme.dart';

/// Tappable file chip for audio/file messages
class TappableFileChip extends StatelessWidget {
  final Event event;
  final bool isMe;
  final IconData icon;
  final String typeLabel;
  final VoidCallback onTap;

  const TappableFileChip({
    super.key,
    required this.event,
    required this.isMe,
    required this.icon,
    required this.typeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Parse file size
    String sizeStr = '';
    try {
      final info = event.content['info'] as Map<String, dynamic>?;
      if (info != null && info['size'] != null) {
        final size = info['size'] is int
            ? info['size'] as int
            : int.tryParse(info['size'].toString()) ?? 0;
        if (size > 0) {
          if (size < 1024) {
            sizeStr = '$size B';
          } else if (size < 1024 * 1024) {
            sizeStr = '${(size / 1024).toStringAsFixed(1)} KB';
          } else {
            sizeStr = '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
          }
        }
      }
    } catch (_) {}

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMe
                  ? kLimeGreen.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isMe ? kLimeGreen : kWhite, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.body,
                  style: GoogleFonts.inter(
                    color: isMe ? kLimeGreen : kWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sizeStr.isNotEmpty) ...[
                      Text(
                        '$sizeStr • ',
                        style: GoogleFonts.inter(
                          color: isMe ? kLimeGreen.withValues(alpha: 0.6) : kLightGrey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    Text(
                      typeLabel,
                      style: GoogleFonts.inter(
                        color: isMe ? kLimeGreen : kLightGrey,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.download_outlined,
                      color: isMe ? kLimeGreen : kLightGrey,
                      size: 12,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
