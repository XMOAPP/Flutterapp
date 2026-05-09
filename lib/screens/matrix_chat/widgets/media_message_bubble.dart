import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../../theme.dart';
import 'image_content.dart';
import 'video_content.dart';

/// Media message bubble (images and videos) with overlay timestamp
class MediaMessageBubble extends StatelessWidget {
  final Event event;
  final bool isMe;
  final String senderName;
  final String time;
  final bool isImage;
  final Future<Uint8List?> Function(Event, {bool getThumbnail}) loadImageBytes;
  final Future<Uint8List?> Function(Event) loadVideoThumbnail;
  final Future<void> Function(Event) playVideo;
  final void Function(Uint8List, String, Event) openFullscreenImage;
  final Widget Function(Event) buildMessageStatus;

  const MediaMessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.senderName,
    required this.time,
    required this.isImage,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
    required this.playVideo,
    required this.openFullscreenImage,
    required this.buildMessageStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Text(
              senderName,
              style: GoogleFonts.inter(
                color: kLimeGreen,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Stack(
          children: [
            if (isImage)
              ImageContent(
                event: event,
                loadImageBytes: loadImageBytes,
                openFullscreenImage: openFullscreenImage,
              )
            else
              VideoContent(
                event: event,
                loadVideoThumbnail: loadVideoThumbnail,
                playVideo: playVideo,
              ),
            // Tick and time overlay at bottom-right inside the media
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isMe) ...[
                      const Icon(
                        Icons.done_all,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      time,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
