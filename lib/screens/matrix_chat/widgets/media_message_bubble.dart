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
  final bool isEdited;

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
    this.isEdited = false,
  });

  @override
  Widget build(BuildContext context) {
    final caption = event.content['xmo_caption'] is String
        ? (event.content['xmo_caption'] as String).trim()
        : '';
    final durationMs = isImage ? null : _videoDurationMs;

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
            if (durationMs != null && durationMs > 0)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formatDuration(durationMs),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
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
                child: _buildTimeRow(color: Colors.white),
              ),
            ),
          ],
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildCaptionBubble(caption),
        ],
      ],
    );
  }

  int? get _videoDurationMs {
    final info = event.content['info'];
    if (info is! Map) return null;
    final raw = info['duration'];
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildCaptionBubble(String caption) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1A2A1A) : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isMe ? 18 : 4),
            topRight: const Radius.circular(18),
            bottomLeft: const Radius.circular(18),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: Text(
          caption,
          style: GoogleFonts.inter(
            color: isMe ? kLimeGreen : kWhite,
            fontSize: 14,
            height: 1.25,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRow({required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: GoogleFonts.inter(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.done_all,
            color: color,
            size: 14,
          ),
        ],
        if (isEdited) ...[
          const SizedBox(width: 4),
          Text(
            'edited',
            style: GoogleFonts.inter(
              color: color.withValues(alpha: 0.75),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
