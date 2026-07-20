import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../services/matrix_service.dart';
import '../../../theme.dart';

final Map<String, Future<Event?>> _replyEventFutures = {};
final Map<String, Future<Uint8List?>> _replyThumbnailFutures = {};
const int _maxReplyEventCacheEntries = 200;
const int _maxReplyThumbnailCacheEntries = 80;

void _trimOldestEntry<T>(Map<String, T> cache, int maxEntries) {
  if (cache.length < maxEntries || cache.isEmpty) return;
  cache.remove(cache.keys.first);
}

String? matrixReplyEventId(Event event) {
  final relatesTo = event.content['m.relates_to'];
  if (relatesTo is! Map) return null;
  final inReplyTo = relatesTo['m.in_reply_to'];
  if (inReplyTo is! Map) return null;
  final eventId = inReplyTo['event_id'];
  return eventId is String && eventId.isNotEmpty ? eventId : null;
}

bool hasMatrixReply(Event event) => matrixReplyEventId(event) != null;

class MessageReplyContext extends StatelessWidget {
  final Event event;
  final bool isMe;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;
  final ValueChanged<String>? onTap;
  final double? width;

  const MessageReplyContext({
    super.key,
    required this.event,
    required this.isMe,
    this.loadImageBytes,
    this.loadVideoThumbnail,
    this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final replyEventId = matrixReplyEventId(event);
    if (replyEventId == null) return const SizedBox.shrink();

    final cacheKey = '${event.room.id}|$replyEventId';
    if (!_replyEventFutures.containsKey(cacheKey)) {
      _trimOldestEntry(_replyEventFutures, _maxReplyEventCacheEntries);
    }
    final future = _replyEventFutures.putIfAbsent(
      cacheKey,
      () async {
        try {
          return await event.room.getEventById(replyEventId);
        } catch (_) {
          return null;
        }
      },
    );

    return FutureBuilder<Event?>(
      future: future,
      builder: (context, snapshot) {
        final replyEvent = snapshot.data;
        final sender = replyEvent == null
            ? 'Message'
            : MatrixService.cleanName(replyEvent.senderId);
        final preview = replyEvent == null
            ? 'Original message unavailable'
            : _replyPreviewText(replyEvent);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap?.call(replyEventId),
          child: Container(
            width: width,
            constraints: BoxConstraints(maxWidth: width ?? 230),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isMe
                  ? const Color(0xFF29452B)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
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
                _ReplyThumbnail(
                  event: replyEvent,
                  isMe: isMe,
                  loadImageBytes: loadImageBytes,
                  loadVideoThumbnail: loadVideoThumbnail,
                ),
                if (_hasReplyMediaPreview(replyEvent)) const SizedBox(width: 7),
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
}

String _replyPreviewText(Event event) {
  switch (event.messageType) {
    case MessageTypes.Image:
      return 'Photo';
    case MessageTypes.Video:
      return 'Video';
    case MessageTypes.Audio:
      return event.content['org.matrix.msc3245.voice'] == true
          ? 'Voice message'
          : 'Audio';
    case MessageTypes.File:
      return event.body.isEmpty ? 'File' : event.body;
    default:
      if (event.type == EventTypes.Sticker) return 'Sticker';
      final body = _stripReplyFallback(event.body).trim();
      return body.isEmpty ? 'Message' : body;
  }
}

bool _hasReplyMediaPreview(Event? event) =>
    event != null &&
    (event.messageType == MessageTypes.Image ||
        event.messageType == MessageTypes.Video ||
        event.messageType == MessageTypes.Audio ||
        event.messageType == MessageTypes.File);

class _ReplyThumbnail extends StatelessWidget {
  final Event? event;
  final bool isMe;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;

  const _ReplyThumbnail({
    required this.event,
    required this.isMe,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
  });

  @override
  Widget build(BuildContext context) {
    final source = event;
    if (!_hasReplyMediaPreview(source)) return const SizedBox.shrink();
    if (source!.messageType == MessageTypes.Audio ||
        source.messageType == MessageTypes.File) {
      return _ReplyTypeIcon(messageType: source.messageType, isMe: isMe);
    }
    final isImage = source.messageType == MessageTypes.Image;
    final cacheKey = '${source.room.id}|${source.eventId}|$isImage';
    if (!_replyThumbnailFutures.containsKey(cacheKey)) {
      _trimOldestEntry(
        _replyThumbnailFutures,
        _maxReplyThumbnailCacheEntries,
      );
    }
    final future = _replyThumbnailFutures.putIfAbsent(cacheKey, () {
      if (isImage) {
        return loadImageBytes?.call(source, getThumbnail: true) ??
            Future<Uint8List?>.value();
      }
      return loadVideoThumbnail?.call(source) ?? Future<Uint8List?>.value();
    });

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1A2A1A) : kDarkGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return _ThumbnailFallback(isImage: isImage, isMe: isMe);
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _ThumbnailFallback(isImage: isImage, isMe: isMe),
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
        },
      ),
    );
  }
}

class _ReplyTypeIcon extends StatelessWidget {
  final String messageType;
  final bool isMe;

  const _ReplyTypeIcon({required this.messageType, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1A2A1A) : kDarkGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        messageType == MessageTypes.Audio
            ? Icons.headphones_rounded
            : Icons.insert_drive_file_rounded,
        color: isMe ? kLimeGreen : kLightGrey,
        size: 20,
      ),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  final bool isImage;
  final bool isMe;

  const _ThumbnailFallback({required this.isImage, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Icon(
      isImage ? Icons.image_outlined : Icons.play_arrow_rounded,
      color: isMe ? kLimeGreen : kLightGrey,
      size: 20,
    );
  }
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
