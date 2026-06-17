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
  final Future<void> Function(Event)? downloadAttachment;
  final Future<void> Function(Event)? shareAttachment;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  final bool isPinned;
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
    this.downloadAttachment,
    this.shareAttachment,
    this.onReply,
    this.onForward,
    this.onPin,
    this.onDelete,
    this.isPinned = false,
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
    final mediaBorderRadius = BorderRadius.circular(isImage ? 20 : 16);

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                borderRadius: mediaBorderRadius,
              )
            else
              VideoContent(
                event: event,
                loadVideoThumbnail: loadVideoThumbnail,
                playVideo: playVideo,
                borderRadius: mediaBorderRadius,
              ),
            if (durationMs != null && durationMs > 0)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
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
            Positioned(
              top: 4,
              right: 4,
              child: _MediaMessageMenu(
                onDownload: downloadAttachment == null
                    ? null
                    : () => downloadAttachment!(event),
                onShare: shareAttachment == null
                    ? null
                    : () => shareAttachment!(event),
                onReply: onReply,
                onForward: onForward,
                onPin: onPin,
                onDelete: onDelete,
                isPinned: isPinned,
              ),
            ),
            // Tick and time overlay at bottom-right inside the media.
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
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
    final textStyle = GoogleFonts.inter(
      color: isMe ? kLimeGreen : kWhite,
      fontSize: 14,
      height: 1.25,
    );

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
        child: _CaptionText(
          caption: caption,
          style: textStyle,
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
          buildMessageStatus(event),
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

class _CaptionText extends StatelessWidget {
  final String caption;
  final TextStyle style;

  const _CaptionText({
    required this.caption,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _captionSegments(caption);

    return Wrap(
      spacing: 0,
      runSpacing: 0,
      children: [
        for (final segment in segments)
          Text(
            segment,
            style: style,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: true,
            ),
          ),
      ],
    );
  }

  List<String> _captionSegments(String value) {
    final result = <String>[];
    final buffer = StringBuffer();

    for (final char in value.characters) {
      if (_isEmojiLike(char)) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
        result.add(char);
      } else {
        buffer.write(char);
        if (char == ' ' || char == '\n') {
          result.add(buffer.toString());
          buffer.clear();
        }
      }
    }

    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }

  bool _isEmojiLike(String value) {
    for (final codePoint in value.runes) {
      if ((codePoint >= 0x1F000 && codePoint <= 0x1FAFF) ||
          (codePoint >= 0x2600 && codePoint <= 0x27BF)) {
        return true;
      }
    }
    return false;
  }
}

class _MediaMessageMenu extends StatelessWidget {
  final VoidCallback? onDownload;
  final VoidCallback? onShare;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  final bool isPinned;

  const _MediaMessageMenu({
    this.onDownload,
    this.onShare,
    this.onReply,
    this.onForward,
    this.onPin,
    this.onDelete,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      tooltip: 'Media options',
      color: const Color(0xFF262728),
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 168),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.more_vert, color: kWhite, size: 21),
      ),
      onSelected: (value) {
        switch (value) {
          case 'reply':
            onReply?.call();
            break;
          case 'forward':
            onForward?.call();
            break;
          case 'download':
            onDownload?.call();
            break;
          case 'share':
            onShare?.call();
            break;
          case 'pin':
            onPin?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (onReply != null) _menuItem('reply', Icons.reply, 'Reply'),
        if (onForward != null)
          _menuItem('forward', Icons.reply, 'Forward', flipIcon: true),
        if (onDownload != null)
          _menuItem('download', Icons.download, 'Download'),
        if (onShare != null) _menuItem('share', Icons.share, 'Share'),
        if (onPin != null)
          _menuItem(
            'pin',
            isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            isPinned ? 'Unpin' : 'Pin',
          ),
        if (onDelete != null)
          _menuItem(
            'delete',
            Icons.delete_outline,
            'Delete',
            color: Colors.redAccent,
          ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color color = kWhite,
    bool flipIcon = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Transform.scale(
            scaleX: flipIcon ? -1 : 1,
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(color: color, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
