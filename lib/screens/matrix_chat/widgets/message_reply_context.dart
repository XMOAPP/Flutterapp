import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../services/matrix_service.dart';
import '../../../theme.dart';
import '../../../utils/message_presentation.dart';

export '../../../utils/message_presentation.dart'
    show hasMatrixReply, matrixReplyEventId;

final Map<String, Future<Event?>> _replyEventFutures = {};
final Map<String, Future<Uint8List?>> _replyThumbnailFutures = {};
const int _maxReplyEventCacheEntries = 200;
const int _maxReplyThumbnailCacheEntries = 80;

void _trimOldestEntry<T>(Map<String, T> cache, int maxEntries) {
  if (cache.length < maxEntries || cache.isEmpty) return;
  cache.remove(cache.keys.first);
}

class MessageReplyContext extends StatelessWidget {
  final Event event;
  final Event? replySourceEvent;
  final bool isMe;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;
  final Event Function(Event)? resolveDisplayEvent;
  final ValueChanged<String>? onTap;
  final double? width;

  const MessageReplyContext({
    super.key,
    required this.event,
    this.replySourceEvent,
    required this.isMe,
    this.loadImageBytes,
    this.loadVideoThumbnail,
    this.resolveDisplayEvent,
    this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final relationEvent = replySourceEvent ?? event;
    final replyEventId = matrixReplyEventId(relationEvent);
    if (replyEventId == null) return const SizedBox.shrink();

    final cacheKey = '${relationEvent.room.id}|$replyEventId';
    if (!_replyEventFutures.containsKey(cacheKey)) {
      _trimOldestEntry(_replyEventFutures, _maxReplyEventCacheEntries);
    }
    final future = _replyEventFutures.putIfAbsent(
      cacheKey,
      () async {
        try {
          return await relationEvent.room.getEventById(replyEventId);
        } catch (_) {
          return null;
        }
      },
    );

    return FutureBuilder<Event?>(
      future: future,
      builder: (context, snapshot) {
        final sourceReplyEvent = snapshot.data;
        final replyEvent = sourceReplyEvent == null
            ? null
            : (resolveDisplayEvent?.call(sourceReplyEvent) ?? sourceReplyEvent);
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
            padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
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
      final filename = event.content['filename'];
      if (filename is String && filename.trim().isNotEmpty) {
        return filename.trim();
      }
      final body = matrixVisibleBody(event).trim();
      return body.isEmpty ? 'File' : body;
    default:
      if (event.type == EventTypes.Sticker) return 'Sticker';
      final body = matrixVisibleBody(event).trim();
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
        borderRadius: BorderRadius.circular(4),
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
