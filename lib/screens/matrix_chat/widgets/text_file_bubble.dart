import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../../theme.dart';
import '../../../services/matrix_service.dart';
import 'audio_message_bubble.dart';
import 'tappable_file_chip.dart';

/// Text or file message bubble with rounded corners
class TextOrFileMessageBubble extends StatelessWidget {
  final Event event;
  final bool isMe;
  final String senderName;
  final String time;
  final bool isAudio;
  final bool isFile;
  final Future<void> Function(Event) downloadAndOpenFile;
  final Future<MatrixFile> Function(Event)? downloadAttachment;
  final Widget Function(Event) buildMessageStatus;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;
  final bool isEdited;
  final ValueChanged<String>? onReplyTap;

  const TextOrFileMessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.senderName,
    required this.time,
    required this.isAudio,
    required this.isFile,
    required this.downloadAndOpenFile,
    this.downloadAttachment,
    required this.buildMessageStatus,
    this.loadImageBytes,
    this.loadVideoThumbnail,
    this.isEdited = false,
    this.onReplyTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayBody = _stripReplyFallback(event.body);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: isAudio ? 3 : 10,
      ),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1A2A1A) : const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isMe ? 18 : 4),
          topRight: const Radius.circular(18),
          bottomLeft: const Radius.circular(18),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                senderName,
                style: GoogleFonts.inter(
                  color: kLimeGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Audio message
          if (isAudio)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (downloadAttachment != null)
                  AudioMessageBubble(
                    event: event,
                    isMe: isMe,
                    time: time,
                    downloadAttachment: downloadAttachment!,
                    buildMessageStatus: buildMessageStatus,
                  )
                else
                  TappableFileChip(
                    event: event,
                    isMe: isMe,
                    icon: Icons.headphones_outlined,
                    typeLabel: 'Audio',
                    onTap: () => downloadAndOpenFile(event),
                  ),
                if (downloadAttachment == null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        time,
                        style: GoogleFonts.inter(
                          color: isMe
                              ? kLimeGreen.withValues(alpha: 0.6)
                              : kLightGrey,
                          fontSize: 10,
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
                            color: isMe
                                ? kLimeGreen.withValues(alpha: 0.45)
                                : kLightGrey.withValues(alpha: 0.75),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            )
          // File message
          else if (isFile)
            SizedBox(
              width: 238,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TappableFileChip(
                    event: event,
                    isMe: isMe,
                    icon: Icons.insert_drive_file_outlined,
                    typeLabel: 'File',
                    onTap: () => downloadAndOpenFile(event),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          time,
                          style: GoogleFonts.inter(
                            color: isMe
                                ? kLimeGreen.withValues(alpha: 0.6)
                                : kLightGrey,
                            fontSize: 10,
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
                              color: isMe
                                  ? kLimeGreen.withValues(alpha: 0.45)
                                  : kLightGrey.withValues(alpha: 0.75),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )
          // Text message
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReplyContextPreview(
                  event: event,
                  isMe: isMe,
                  loadImageBytes: loadImageBytes,
                  loadVideoThumbnail: loadVideoThumbnail,
                  onReplyTap: onReplyTap,
                ),
                if (_replyToEventId(event) != null) const SizedBox(height: 6),
                Text(
                  displayBody,
                  style: GoogleFonts.inter(
                    color: isMe ? kLimeGreen : kWhite,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      time,
                      style: GoogleFonts.inter(
                        color: isMe
                            ? kLimeGreen.withValues(alpha: 0.6)
                            : kLightGrey,
                        fontSize: 10,
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
                          color: isMe
                              ? kLimeGreen.withValues(alpha: 0.45)
                              : kLightGrey.withValues(alpha: 0.75),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String? _replyToEventId(Event event) {
  final relatesTo = event.content['m.relates_to'];
  if (relatesTo is! Map) return null;

  final inReplyTo = relatesTo['m.in_reply_to'];
  if (inReplyTo is! Map) return null;

  final eventId = inReplyTo['event_id'];
  return eventId is String && eventId.isNotEmpty ? eventId : null;
}

String _stripReplyFallback(String body) {
  final lines = body.replaceAll('\r\n', '\n').split('\n');
  if (lines.isEmpty || !lines.first.startsWith('> ')) return body;

  var index = 0;
  while (index < lines.length && lines[index].startsWith('> ')) {
    index++;
  }
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }

  final stripped = lines.skip(index).join('\n').trim();
  return stripped.isEmpty ? body : stripped;
}

class _ReplyContextPreview extends StatelessWidget {
  final Event event;
  final bool isMe;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;
  final ValueChanged<String>? onReplyTap;

  const _ReplyContextPreview({
    required this.event,
    required this.isMe,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
    required this.onReplyTap,
  });

  @override
  Widget build(BuildContext context) {
    final replyEventId = _replyToEventId(event);
    if (replyEventId == null) return const SizedBox.shrink();

    return FutureBuilder<Event?>(
      future: event.room.getEventById(replyEventId),
      builder: (context, snapshot) {
        final replyEvent = snapshot.data;
        final sender = replyEvent == null
            ? 'Message'
            : MatrixService.cleanName(replyEvent.senderId);
        final preview = replyEvent == null
            ? 'Original message'
            : _replyPreviewText(replyEvent);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onReplyTap?.call(replyEventId),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 230),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isMe
                  ? const Color(0xFF29452B)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 3,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isMe ? kLimeGreen : const Color(0xFF72B7F2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 7),
                _ReplyMediaThumb(
                  event: replyEvent,
                  isMe: isMe,
                  loadImageBytes: loadImageBytes,
                  loadVideoThumbnail: loadVideoThumbnail,
                ),
                if (_hasMediaThumb(replyEvent)) const SizedBox(width: 7),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sender,
                        style: GoogleFonts.inter(
                          color: isMe ? kLimeGreen : const Color(0xFF72B7F2),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        style: GoogleFonts.inter(
                          color: isMe
                              ? kLimeGreen.withValues(alpha: 0.72)
                              : kLightGrey,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _replyPreviewText(Event event) {
    switch (event.messageType) {
      case MessageTypes.Image:
        return 'Photo';
      case MessageTypes.Video:
        return 'Video';
      case MessageTypes.Audio:
        return 'Audio';
      case MessageTypes.File:
        return event.body.isEmpty ? 'File' : event.body;
      default:
        return _stripReplyFallback(event.body);
    }
  }
}

bool _hasMediaThumb(Event? event) {
  return event != null &&
      (event.messageType == MessageTypes.Image ||
          event.messageType == MessageTypes.Video);
}

class _ReplyMediaThumb extends StatelessWidget {
  final Event? event;
  final bool isMe;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;

  const _ReplyMediaThumb({
    required this.event,
    required this.isMe,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
  });

  @override
  Widget build(BuildContext context) {
    if (!_hasMediaThumb(event)) return const SizedBox.shrink();

    final isImage = event!.messageType == MessageTypes.Image;
    final thumbFuture = isImage
        ? loadImageBytes?.call(event!, getThumbnail: true)
        : loadVideoThumbnail?.call(event!);

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1A2A1A) : kDarkGrey,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        future: thumbFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _ReplyThumbFallback(isImage: isImage, isMe: isMe),
                ),
                if (!isImage)
                  Container(
                    color: Colors.black.withValues(alpha: 0.18),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
              ],
            );
          }

          return _ReplyThumbFallback(isImage: isImage, isMe: isMe);
        },
      ),
    );
  }
}

class _ReplyThumbFallback extends StatelessWidget {
  final bool isImage;
  final bool isMe;

  const _ReplyThumbFallback({
    required this.isImage,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      isImage ? Icons.image_outlined : Icons.play_arrow_rounded,
      color: isMe ? kLimeGreen : kLightGrey,
      size: 20,
    );
  }
}
