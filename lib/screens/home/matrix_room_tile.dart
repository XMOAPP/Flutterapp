import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/matrix_service.dart';
import '../../services/matrix_media_helper.dart';
import '../../widgets/story/story_avatar.dart';
import '../../utils/message_presentation.dart';
import '../matrix_chat/widgets/tappable_file_chip.dart';
import '../matrix_chat/media_handler.dart';
import '../matrix_chat_screen.dart';

/// Matrix room tile for displaying Matrix rooms in the chat list
class MatrixRoomTile extends StatefulWidget {
  final Room room;
  final bool showUnreadBadge;
  final Widget? trailing;

  const MatrixRoomTile({
    super.key,
    required this.room,
    this.showUnreadBadge = true,
    this.trailing,
  });

  @override
  State<MatrixRoomTile> createState() => _MatrixRoomTileState();
}

class _MatrixRoomTileState extends State<MatrixRoomTile> {
  String? _fallbackPreviewKey;
  Future<Event?>? _fallbackPreviewFuture;

  @override
  Widget build(BuildContext context) {
    final lastEvent = widget.room.lastEvent;
    if (lastEvent?.redacted == true) {
      final fallbackKey =
          '${widget.room.id}:${lastEvent!.eventId}:${lastEvent.originServerTs.millisecondsSinceEpoch}';
      if (_fallbackPreviewKey != fallbackKey) {
        _fallbackPreviewKey = fallbackKey;
        _fallbackPreviewFuture = _latestVisiblePreviewEvent(widget.room);
      }

      return FutureBuilder<Event?>(
        future: _fallbackPreviewFuture,
        builder: (context, snapshot) => _buildTile(
          context,
          previewEvent: snapshot.data,
        ),
      );
    }

    return _buildTile(context, previewEvent: lastEvent);
  }

  Widget _buildTile(BuildContext context, {required Event? previewEvent}) {
    final room = widget.room;
    final matrixService = MatrixService();
    final isDirect = matrixService.isDirectRoom(room);
    final isSavedMessages = matrixService.isSavedMessagesRoom(room);
    final cleanedName = isSavedMessages
        ? 'Saved Messages'
        : MatrixService.cleanName(matrixService.getResolvedDisplayName(room));
    final unreadCount = room.notificationCount;
    final lastEventTime = _formatLastEventTime(previewEvent?.originServerTs);

    final preview = previewEvent != null
        ? _buildLastMessagePreview(
            previewEvent,
            matrixService: matrixService,
            unread: unreadCount > 0,
          )
        : Text(
            'No messages yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: unreadCount > 0 ? _unreadSubtitleStyle : _subtitleStyle,
          );

    final avatar = StoryAvatar(
      userName: cleanedName,
      avatarUrl: room.avatar?.toString(),
      size: 50,
      fallbackIcon: isSavedMessages
          ? Icons.bookmark
          : !isDirect && room.isChannel
              ? Icons.campaign
              : !isDirect && room.isGroup
                  ? Icons.group
                  : null,
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _showAvatarPreview(context, cleanedName),
        child: avatar,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              cleanedName,
              style: _titleStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isDirect && (room.isChannel || room.isGroup)) ...[
            const SizedBox(width: 8),
            room.isChannel ? const ChannelBadge() : const GroupBadge(),
          ],
        ],
      ),
      subtitle: preview,
      trailing: widget.trailing ??
          (lastEventTime != null || (widget.showUnreadBadge && unreadCount > 0)
              ? _RoomMeta(
                  time: lastEventTime,
                  unreadCount: widget.showUnreadBadge ? unreadCount : 0,
                )
              : null),
      onTap: () async {
        final matrixProvider = context.read<MatrixProvider>();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatrixChatScreen(
              room: room,
              matrixProvider: matrixProvider,
            ),
          ),
        );
        if (context.mounted) {
          matrixProvider.refreshRooms();
        }
      },
    );
  }

  static Future<Event?> _latestVisiblePreviewEvent(Room room) async {
    try {
      final timeline = await room.getTimeline();
      for (final event in timeline.events) {
        if (_isPreviewCandidate(event)) return event;
      }
    } catch (_) {
      // Keep the room tile usable if the local timeline is not available yet.
    }
    return null;
  }

  static bool _isPreviewCandidate(Event event) {
    if (event.redacted) return false;
    if (_isEditReplacementEvent(event)) return false;
    if (MatrixService.isGroupCallPushMarker(event)) return false;
    return event.type == EventTypes.Message ||
        event.type == EventTypes.Encrypted;
  }

  static bool _isEditReplacementEvent(Event event) {
    return event.relationshipType == RelationshipTypes.edit &&
        event.relationshipEventId != null &&
        event.content['m.new_content'] is Map;
  }

  void _showAvatarPreview(BuildContext context, String name) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, _, __) {
        final matrixService = MatrixService();
        final room = widget.room;
        final isDirect = matrixService.isDirectRoom(room);
        final isSavedMessages = matrixService.isSavedMessagesRoom(room);
        final fallbackIcon = isSavedMessages
            ? Icons.bookmark
            : !isDirect && room.isChannel
                ? Icons.campaign
                : !isDirect && room.isGroup
                    ? Icons.group
                    : null;

        return Center(
          child: GestureDetector(
            onTap: () => Navigator.of(dialogContext).pop(),
            child: StoryAvatar(
              userName: name,
              avatarUrl: room.avatar?.toString(),
              size: 220,
              fallbackIcon: fallbackIcon,
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static final _titleStyle = GoogleFonts.inter(
    color: kWhite,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static final _subtitleStyle = GoogleFonts.inter(
    color: kLightGrey,
    fontSize: 13,
  );

  static final _unreadSubtitleStyle = GoogleFonts.inter(
    color: kWhite,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static Widget _buildLastMessagePreview(
    Event event, {
    required MatrixService matrixService,
    required bool unread,
  }) {
    final preview = _lastMessagePreviewData(event, matrixService);
    final textStyle = unread ? _unreadSubtitleStyle : _subtitleStyle;

    if (preview.thumbnailRequest == null &&
        preview.encryptedThumbnailEvent == null &&
        preview.icon == null) {
      return Text(
        preview.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }

    return Row(
      children: [
        if (preview.thumbnailRequest != null)
          _PreviewThumbnail(
            mediaRequest: preview.thumbnailRequest!,
            isVideo: preview.isVideo,
            fallbackIcon: preview.icon ?? Icons.image_rounded,
          )
        else if (preview.encryptedThumbnailEvent != null)
          _EncryptedPreviewThumbnail(
            key: ValueKey(preview.encryptedThumbnailEvent!.eventId),
            event: preview.encryptedThumbnailEvent!,
            isVideo: preview.isVideo,
            fallbackIcon: preview.icon ?? Icons.image_rounded,
          )
        else
          Icon(
            preview.icon!,
            color: preview.iconColor,
            size: 17,
          ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            preview.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle.copyWith(
              color: preview.accentText ? kAudioBlue : textStyle.color,
            ),
          ),
        ),
      ],
    );
  }

  static _LastMessagePreview _lastMessagePreviewData(
    Event event,
    MatrixService matrixService,
  ) {
    final isStoryReply = _isStoryReplyEvent(event);

    if (event.redacted) {
      return const _LastMessagePreview(
        text: 'Deleted message',
        icon: Icons.block_rounded,
        iconColor: kLightGrey,
      );
    }

    if (event.type == EventTypes.Encrypted) {
      return const _LastMessagePreview(
        text: 'Encrypted message',
        icon: Icons.lock_rounded,
        iconColor: kLightGrey,
      );
    }

    if (event.type == 'm.room.member') {
      return const _LastMessagePreview(
        text: 'Room created',
        icon: Icons.group_add_rounded,
        iconColor: kLightGrey,
      );
    }

    if (event.type != EventTypes.Message) {
      return _LastMessagePreview(
        text: _previewBody(event, fallback: 'Message'),
      );
    }

    if (isStoryReply) {
      return _LastMessagePreview(
        text: _storyReplyPreviewBody(event),
        icon: Icons.auto_stories_rounded,
        iconColor: kLightGrey,
      );
    }

    switch (event.messageType) {
      case MessageTypes.Text:
      case MessageTypes.Notice:
      case MessageTypes.Emote:
        return _LastMessagePreview(
          text: _previewBody(event, fallback: 'Message'),
        );
      case MessageTypes.Image:
        return _LastMessagePreview(
          text: _captionOrLabel(event, 'Photo'),
          thumbnailRequest: _mediaThumbnailRequest(event, matrixService),
          encryptedThumbnailEvent: event.isAttachmentEncrypted ? event : null,
          icon: Icons.image_rounded,
          iconColor: kAudioBlue,
          accentText: true,
        );
      case MessageTypes.Video:
        return _LastMessagePreview(
          text: _captionOrLabel(event, 'Video'),
          thumbnailRequest: _mediaThumbnailRequest(event, matrixService),
          encryptedThumbnailEvent:
              event.isThumbnailEncrypted || event.isAttachmentEncrypted
                  ? event
                  : null,
          icon: Icons.videocam_rounded,
          iconColor: kAudioBlue,
          isVideo: true,
          accentText: true,
        );
      case MessageTypes.Audio:
        final duration = _formatDuration(_eventDurationMs(event));
        if (_looksLikeVoiceMessage(event)) {
          return _LastMessagePreview(
            text: 'Voice message${duration == null ? '' : ' ($duration)'}',
            icon: Icons.mic_rounded,
            iconColor: kLightGrey,
          );
        }
        return _LastMessagePreview(
          text: _fileName(event, fallback: 'Audio'),
          icon: Icons.headphones_rounded,
          iconColor: kLightGrey,
          accentText: true,
        );
      case MessageTypes.File:
        final fileName = _fileName(event, fallback: 'File');
        final attachmentType = detectAttachmentType(event);
        return _LastMessagePreview(
          text: fileName,
          icon: attachmentType.icon,
          iconColor: kLightGrey,
        );
      default:
        return _LastMessagePreview(
          text: _previewBody(event, fallback: 'Message'),
        );
    }
  }

  static const String _storyReplyContentKey = 'com.xmo.story_reply';

  static bool _isStoryReplyEvent(Event event) {
    return event.content[_storyReplyContentKey] is Map ||
        event.body.startsWith('Replied to your story\n');
  }

  static String _storyReplyPreviewBody(Event event) {
    final body = _previewBody(event, fallback: '');
    if (body.isEmpty) return 'Story replied';
    return 'Story replied: $body';
  }

  static String _previewBody(Event event, {required String fallback}) {
    final body = _stripStoryReplyFallback(
      matrixVisibleBody(event).trim(),
    );
    final stripped = body.trim();
    return stripped.isEmpty ? fallback : stripped;
  }

  static String _stripStoryReplyFallback(String body) {
    const prefix = 'Replied to your story\n';
    if (!body.startsWith(prefix)) return body;
    return body.substring(prefix.length).trim();
  }

  static String _captionOrLabel(Event event, String label) {
    final caption = event.content['xmo_caption']?.toString().trim();
    if (caption != null && caption.isNotEmpty) return caption;
    return label;
  }

  static bool _looksLikeVoiceMessage(Event event) {
    final body = event.body.toLowerCase();
    final filename = event.content['filename']?.toString().toLowerCase() ?? '';
    return event.content.containsKey('org.matrix.msc3245.voice') ||
        body.startsWith('voice_') ||
        filename.startsWith('voice_');
  }

  static String _fileName(Event event, {required String fallback}) {
    return matrixAttachmentFileName(event, fallback: fallback);
  }

  static MatrixMediaRequest? _mediaThumbnailRequest(
    Event event,
    MatrixService matrixService,
  ) {
    final info = event.content['info'];
    String? mxcUrl;
    if (info is Map) {
      mxcUrl = info['thumbnail_url']?.toString();
    }
    mxcUrl ??= event.content['thumbnail_url']?.toString();
    mxcUrl ??= event.content['url']?.toString();

    return matrixService.getMediaRequest(mxcUrl, width: 32, height: 32);
  }

  static int? _eventDurationMs(Event event) {
    final info = event.content['info'];
    final rawDuration =
        info is Map ? info['duration'] : event.content['duration'];
    if (rawDuration is int) return rawDuration;
    if (rawDuration is num) return rawDuration.toInt();
    return int.tryParse(rawDuration?.toString() ?? '');
  }

  static String? _formatDuration(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return null;
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  static String? _formatLastEventTime(DateTime? timestamp) {
    if (timestamp == null) return null;

    final now = DateTime.now();
    final local = timestamp.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);

    if (messageDay == today) {
      final hour = local.hour == 0
          ? 12
          : local.hour > 12
              ? local.hour - 12
              : local.hour;
      final minute = local.minute.toString().padLeft(2, '0');
      final period = local.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }

    if (messageDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }

    return '${local.day}/${local.month}/${local.year.toString().substring(2)}';
  }
}

class _LastMessagePreview {
  final String text;
  final IconData? icon;
  final Color iconColor;
  final MatrixMediaRequest? thumbnailRequest;
  final Event? encryptedThumbnailEvent;
  final bool isVideo;
  final bool accentText;

  const _LastMessagePreview({
    required this.text,
    this.icon,
    this.iconColor = kLightGrey,
    this.thumbnailRequest,
    this.encryptedThumbnailEvent,
    this.isVideo = false,
    this.accentText = false,
  });
}

class _EncryptedPreviewThumbnail extends StatefulWidget {
  final Event event;
  final bool isVideo;
  final IconData fallbackIcon;

  const _EncryptedPreviewThumbnail({
    super.key,
    required this.event,
    required this.isVideo,
    required this.fallbackIcon,
  });

  @override
  State<_EncryptedPreviewThumbnail> createState() =>
      _EncryptedPreviewThumbnailState();
}

class _EncryptedPreviewThumbnailState
    extends State<_EncryptedPreviewThumbnail> {
  late Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _EncryptedPreviewThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId ||
        oldWidget.isVideo != widget.isVideo) {
      _thumbnailFuture = _loadThumbnail();
    }
  }

  Uint8List? _cachedThumbnail() {
    if (widget.isVideo) {
      return MediaHandler.getCachedThumbnail(widget.event.eventId);
    }
    return MediaHandler.getCachedRoomPreview(widget.event.eventId);
  }

  Future<Uint8List?> _loadThumbnail() {
    final matrixProvider = context.read<MatrixProvider>();
    final mediaHandler = MediaHandler(
      matrixProvider: matrixProvider,
      context: context,
    );
    return widget.isVideo
        ? mediaHandler.loadVideoThumbnail(widget.event)
        : mediaHandler.loadRoomPreviewThumbnail(widget.event);
  }

  @override
  Widget build(BuildContext context) {
    final cached = _cachedThumbnail();
    return FutureBuilder<Uint8List?>(
      initialData: cached,
      future: cached == null ? _thumbnailFuture : null,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: 20,
            height: 20,
            child: bytes == null || bytes.isEmpty
                ? _ThumbnailFallback(icon: widget.fallbackIcon)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        cacheWidth: 40,
                        cacheHeight: 40,
                        errorBuilder: (_, __, ___) =>
                            _ThumbnailFallback(icon: widget.fallbackIcon),
                      ),
                      if (widget.isVideo)
                        Container(
                          color: Colors.black.withValues(alpha: 0.24),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: kWhite,
                            size: 15,
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

class _PreviewThumbnail extends StatelessWidget {
  final MatrixMediaRequest mediaRequest;
  final bool isVideo;
  final IconData fallbackIcon;

  const _PreviewThumbnail({
    required this.mediaRequest,
    required this.isVideo,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 20,
        height: 20,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              mediaRequest.uri.toString(),
              headers: mediaRequest.headers,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _ThumbnailFallback(
                icon: fallbackIcon,
              ),
            ),
            if (isVideo)
              Container(
                color: Colors.black.withValues(alpha: 0.24),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: kWhite,
                  size: 15,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  final IconData icon;

  const _ThumbnailFallback({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: Icon(
        icon,
        color: kLightGrey,
        size: 14,
      ),
    );
  }
}

class _RoomMeta extends StatelessWidget {
  final String? time;
  final int unreadCount;

  const _RoomMeta({
    required this.time,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final metaWidth =
        screenWidth < 340 ? 64.0 : (screenWidth < 380 ? 72.0 : 86.0);

    return SizedBox(
      width: metaWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (time != null)
            Text(
              time!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (unreadCount > 0) ...[
            const SizedBox(height: 6),
            _UnreadBadge(count: unreadCount),
          ],
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: kAudioBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Group badge widget
class GroupBadge extends StatelessWidget {
  const GroupBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.group, color: kLimeGreen, size: 10),
          const SizedBox(width: 2),
          Text(
            'Group',
            style: GoogleFonts.inter(
              color: kLimeGreen,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Channel badge widget
class ChannelBadge extends StatelessWidget {
  const ChannelBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.campaign, color: kLimeGreen, size: 10),
          const SizedBox(width: 2),
          Text(
            'Channel',
            style: GoogleFonts.inter(
              color: kLimeGreen,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
