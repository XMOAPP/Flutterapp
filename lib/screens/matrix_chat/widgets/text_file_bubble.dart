import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../theme.dart';
import '../../../models/group_models.dart';
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
  final Future<void> Function(Event)? shareAttachment;
  final Future<void> Function(Event)? openAttachmentExternally;
  final Future<MatrixFile> Function(Event)? downloadAttachment;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  final bool isPinned;
  final Widget Function(Event) buildMessageStatus;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;
  final bool isEdited;
  final ValueChanged<String>? onReplyTap;
  final List<GroupMember> mentionMembers;
  final ValueChanged<GroupMember>? onMentionTap;

  const TextOrFileMessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.senderName,
    required this.time,
    required this.isAudio,
    required this.isFile,
    required this.downloadAndOpenFile,
    this.shareAttachment,
    this.openAttachmentExternally,
    this.downloadAttachment,
    this.onReply,
    this.onForward,
    this.onPin,
    this.onDelete,
    this.isPinned = false,
    required this.buildMessageStatus,
    this.loadImageBytes,
    this.loadVideoThumbnail,
    this.isEdited = false,
    this.onReplyTap,
    this.mentionMembers = const [],
    this.onMentionTap,
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
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 34),
                    child: TappableFileChip(
                      event: event,
                      isMe: isMe,
                      icon: Icons.insert_drive_file,
                      typeLabel: '',
                      showTypeLabel: true,
                      showDownloadIcon: false,
                      onTap: () {
                        final open = openAttachmentExternally;
                        if (open != null) {
                          open(event);
                        } else {
                          downloadAndOpenFile(event);
                        }
                      },
                    ),
                  ),
                  Positioned(
                    top: -2,
                    right: -8,
                    child: _FileMessageMenu(
                      isMe: isMe,
                      onDownload: () => downloadAndOpenFile(event),
                      onShare: shareAttachment == null
                          ? null
                          : () => shareAttachment!(event),
                      onOpenWith: openAttachmentExternally == null
                          ? null
                          : () => openAttachmentExternally!(event),
                      onReply: onReply,
                      onForward: onForward,
                      onPin: onPin,
                      onDelete: onDelete,
                      isPinned: isPinned,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 50),
                    child: Align(
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
                  ),
                ],
              ),
            )
          // Text message
          else
            IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReplyContextPreview(
                    event: event,
                    isMe: isMe,
                    loadImageBytes: loadImageBytes,
                    loadVideoThumbnail: loadVideoThumbnail,
                    onReplyTap: onReplyTap,
                  ),
                  if (_replyToEventId(event) != null) const SizedBox(height: 6),
                  _MentionAwareText(
                    text: displayBody,
                    members: mentionMembers,
                    baseStyle: GoogleFonts.inter(
                      color: isMe ? kLimeGreen : kWhite,
                      fontSize: 14,
                    ),
                    onMentionTap: onMentionTap,
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
            ),
        ],
      ),
    );
  }
}

class _FileMessageMenu extends StatelessWidget {
  final bool isMe;
  final VoidCallback onDownload;
  final VoidCallback? onShare;
  final VoidCallback? onOpenWith;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  final bool isPinned;

  const _FileMessageMenu({
    required this.isMe,
    required this.onDownload,
    this.onShare,
    this.onOpenWith,
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
      tooltip: 'File options',
      color: const Color(0xFF262728),
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 168),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.more_vert, color: kLimeGreen, size: 21),
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
            onDownload();
            break;
          case 'share':
            onShare?.call();
            break;
          case 'open':
            onOpenWith?.call();
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
        _menuItem('download', Icons.download, 'Download'),
        if (onShare != null) _menuItem('share', Icons.share, 'Share'),
        if (onOpenWith != null)
          _menuItem('open', Icons.open_in_new, 'Open with'),
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

class _MentionAwareText extends StatefulWidget {
  final String text;
  final TextStyle baseStyle;
  final List<GroupMember> members;
  final ValueChanged<GroupMember>? onMentionTap;

  const _MentionAwareText({
    required this.text,
    required this.baseStyle,
    required this.members,
    required this.onMentionTap,
  });

  @override
  State<_MentionAwareText> createState() => _MentionAwareTextState();
}

class _MentionAwareTextState extends State<_MentionAwareText> {
  static final RegExp _linkPattern = RegExp(
    r'(?:(?:https?|ftp)://[^\s<>()]+|(?:mailto:|tel:|sms:|geo:|magnet:|matrix:)[^\s<>()]+|www\.[^\s<>()]+|(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+(?:com|org|net|edu|gov|io|co|in|me|app|dev|ai|info|biz|xyz|site|online|store|tech|link|ly|to|tv|uk|us|ca|au|de|fr|jp|cn|ru|br|za|nl|it|es|se|no|fi|ch|be|at|dk|pl|ie|sg|ae|sa|qa|kw|om|bh|pk|bd|lk|np|id|my|th|vn|ph)(?:/[^\s<>()]*)?)',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final spans = _buildSpans();
    if (spans.length == 1 && spans.first.recognizer == null) {
      return Text(widget.text, style: widget.baseStyle);
    }

    return RichText(
      text: TextSpan(style: widget.baseStyle, children: spans),
    );
  }

  List<TextSpan> _buildSpans() {
    final mentionTargets = widget.members
        .where((member) => member.displayName.trim().isNotEmpty)
        .map(
          (member) => _MentionTarget(
            member: member,
            token: '@${member.displayName.trim()}',
          ),
        )
        .toList()
      ..sort((a, b) => b.token.length.compareTo(a.token.length));

    final spans = <TextSpan>[];
    var index = 0;
    while (index < widget.text.length) {
      final nextToken = _nextToken(index, mentionTargets);
      if (nextToken == null) {
        spans.add(TextSpan(text: widget.text.substring(index)));
        break;
      }

      if (nextToken.start > index) {
        spans
            .add(TextSpan(text: widget.text.substring(index, nextToken.start)));
      }

      spans.add(nextToken.span);
      index = nextToken.end;
    }

    return spans;
  }

  _TextToken? _nextToken(int start, List<_MentionTarget> mentionTargets) {
    _TextToken? best;

    final linkMatch = _nextLinkMatch(start);
    if (linkMatch != null) {
      best = _buildLinkToken(linkMatch);
    }

    if (widget.onMentionTap != null && mentionTargets.isNotEmpty) {
      for (var index = start; index < widget.text.length; index++) {
        if (widget.text.codeUnitAt(index) != 64) continue; // @
        for (final target in mentionTargets) {
          if (!widget.text.startsWith(target.token, index)) continue;
          final token = _buildMentionToken(index, target);
          if (best == null || token.start < best.start) return token;
          return best;
        }
      }
    }

    return best;
  }

  _LinkCandidate? _nextLinkMatch(int start) {
    for (final match in _linkPattern.allMatches(widget.text, start)) {
      final trimmedEnd = _trimLinkEnd(match.group(0)!, match.end);
      if (trimmedEnd > match.start) {
        return _LinkCandidate(match.start, trimmedEnd);
      }
    }
    return null;
  }

  int _trimLinkEnd(String value, int originalEnd) {
    const trailing = '.,;:!?)]}\'"';
    var end = originalEnd;
    var text = value;
    while (text.isNotEmpty && trailing.contains(text[text.length - 1])) {
      text = text.substring(0, text.length - 1);
      end--;
    }
    return end;
  }

  _TextToken _buildLinkToken(_LinkCandidate match) {
    final visibleText = widget.text.substring(match.start, match.end);
    final recognizer = TapGestureRecognizer()
      ..onTap = () => _openLink(visibleText);
    _recognizers.add(recognizer);

    return _TextToken(
      start: match.start,
      end: match.end,
      span: TextSpan(
        text: visibleText,
        style: widget.baseStyle.copyWith(
          color: kAudioBlue,
        ),
        recognizer: recognizer,
      ),
    );
  }

  _TextToken _buildMentionToken(int start, _MentionTarget target) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onMentionTap?.call(target.member);
    _recognizers.add(recognizer);

    return _TextToken(
      start: start,
      end: start + target.token.length,
      span: TextSpan(
        text: target.token,
        style: widget.baseStyle.copyWith(
          color: kAudioBlue,
          fontWeight: FontWeight.w700,
        ),
        recognizer: recognizer,
      ),
    );
  }

  Future<void> _openLink(String rawLink) async {
    final uri = _uriForLink(rawLink);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication) ||
        await launchUrl(uri, mode: LaunchMode.platformDefault);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open link: $rawLink'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Uri? _uriForLink(String rawLink) {
    final trimmed = rawLink.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return uri;

    return Uri.tryParse('https://$trimmed');
  }
}

class _LinkCandidate {
  final int start;
  final int end;

  const _LinkCandidate(this.start, this.end);
}

class _TextToken {
  final int start;
  final int end;
  final TextSpan span;

  const _TextToken({
    required this.start,
    required this.end,
    required this.span,
  });
}

class _MentionTarget {
  final GroupMember member;
  final String token;

  const _MentionTarget({
    required this.member,
    required this.token,
  });
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
