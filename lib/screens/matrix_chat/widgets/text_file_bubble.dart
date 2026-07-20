import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../theme.dart';
import '../../../models/group_models.dart';
import '../../../models/xmo_contact_card.dart';
import '../../../providers/matrix_provider.dart';
import '../../../providers/story_provider.dart';
import '../../../services/matrix_media_helper.dart';
import '../../story/story_viewer_screen.dart';
import '../media_handler.dart';
import 'audio_message_bubble.dart';
import 'message_reply_context.dart';
import 'tappable_file_chip.dart';
import 'package:provider/provider.dart';

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
  final MatrixMediaRequest? Function(Event)? streamingMediaRequest;
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
  final void Function(String roomId, String eventId)? onPrivateReplyTap;
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
    this.streamingMediaRequest,
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
    this.onPrivateReplyTap,
    this.mentionMembers = const [],
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final contact = XmoContactCard.fromEventContent(event.content);
    final storyReply = _storyReplyContent(event);
    final displayBody = _storyReplyDisplayBody(
      _stripReplyFallback(event.body),
      storyReply,
    );
    final hasReply = hasMatrixReply(event);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final audioBubbleWidth = math.min(
      330.0,
      math.max(160.0, screenWidth * 0.78),
    );
    final fileBubbleWidth = math.min(
      238.0,
      math.max(180.0, screenWidth * 0.66),
    );
    final replyContextWidth = isAudio
        ? audioBubbleWidth
        : isFile
            ? fileBubbleWidth
            : null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        isAudio && !hasReply ? 3 : 10,
        14,
        isAudio ? 3 : 10,
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
          MessageReplyContext(
            event: event,
            isMe: isMe,
            loadImageBytes: loadImageBytes,
            loadVideoThumbnail: loadVideoThumbnail,
            onTap: onReplyTap,
            width: replyContextWidth,
          ),
          if (hasReply) const SizedBox(height: 6),
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
                    streamingMediaRequest: streamingMediaRequest,
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
          else if (isFile && contact != null)
            SizedBox(
              width: fileBubbleWidth,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 34),
                    child: _ContactMessageCard(
                      contact: contact,
                      isMe: isMe,
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
                    padding: const EdgeInsets.only(top: 66),
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
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          // File message
          else if (isFile)
            SizedBox(
              width: fileBubbleWidth,
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
                  _StoryReplyContextPreview(
                    storyReply: storyReply,
                    isMe: isMe,
                  ),
                  _PrivateReplyContextPreview(
                    event: event,
                    isMe: isMe,
                    loadImageBytes: loadImageBytes,
                    loadVideoThumbnail: loadVideoThumbnail,
                    onTap: onPrivateReplyTap,
                  ),
                  if (storyReply != null || _privateReplyContent(event) != null)
                    const SizedBox(height: 6),
                  _MentionAwareText(
                    text: displayBody,
                    members: mentionMembers,
                    baseStyle: GoogleFonts.inter(
                      color: isMe ? kLimeGreen : kWhite,
                      fontSize: _containsEmoji(displayBody) ? 17 : 14,
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

class _ContactMessageCard extends StatelessWidget {
  final XmoContactCard contact;
  final bool isMe;
  final VoidCallback onTap;

  const _ContactMessageCard({
    required this.contact,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = isMe ? kLimeGreen : kWhite;
    return Material(
      color: isMe
          ? kLimeGreen.withValues(alpha: 0.1)
          : kWhite.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_outline, color: foreground, size: 25),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contact.phoneNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: isMe
                            ? kLimeGreen.withValues(alpha: 0.68)
                            : kLightGrey,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

bool _containsEmoji(String text) {
  for (final rune in text.runes) {
    final isEmoji = (rune >= 0x1F000 && rune <= 0x1FAFF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        (rune >= 0x2B00 && rune <= 0x2BFF) ||
        (rune >= 0x1F1E6 && rune <= 0x1F1FF) ||
        (rune >= 0x1F3FB && rune <= 0x1F3FF);
    if (isEmoji) return true;
  }
  return false;
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

Map<String, dynamic>? _privateReplyContent(Event event) {
  final raw = event.content['com.xmo.private_reply'];
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

final Map<String, Future<Event?>> _replyPreviewEventFutures = {};
final Map<String, Future<Uint8List?>> _replyPreviewMediaFutures = {};

Future<Event?> _cachedReplyPreviewEvent(Room room, String eventId) {
  final trimmedEventId = eventId.trim();
  if (trimmedEventId.isEmpty) return Future<Event?>.value(null);
  final key = '${room.id}:$trimmedEventId';
  return _replyPreviewEventFutures.putIfAbsent(key, () async {
    try {
      return room.getEventById(trimmedEventId);
    } catch (_) {
      return null;
    }
  });
}

Uint8List? _cachedReplyPreviewMediaBytes(Event event, bool isImage) {
  return isImage
      ? MediaHandler.getCachedImageBytes(event.eventId, getThumbnail: true)
      : MediaHandler.getCachedThumbnail(event.eventId);
}

Future<Uint8List?>? _cachedReplyPreviewMediaFuture(
  Event event,
  bool isImage,
  Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes,
  Future<Uint8List?> Function(Event)? loadVideoThumbnail,
) {
  final key =
      '${event.room.id}:${event.eventId}:${isImage ? 'image' : 'video'}';
  return _replyPreviewMediaFutures.putIfAbsent(key, () {
    return isImage
        ? loadImageBytes?.call(event, getThumbnail: true) ??
            Future<Uint8List?>.value(null)
        : loadVideoThumbnail?.call(event) ?? Future<Uint8List?>.value(null);
  });
}

class _PrivateReplyContextPreview extends StatelessWidget {
  final Event event;
  final bool isMe;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;
  final void Function(String roomId, String eventId)? onTap;

  const _PrivateReplyContextPreview({
    required this.event,
    required this.isMe,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final privateReply = _privateReplyContent(event);
    if (privateReply == null) return const SizedBox.shrink();

    final sender = (privateReply['sender_name'] as String?)?.trim();
    final preview = (privateReply['preview'] as String?)?.trim();
    final sourceRoomId = (privateReply['source_room_id'] as String?)?.trim();
    final sourceEventId = (privateReply['source_event_id'] as String?)?.trim();
    final msgtype = (privateReply['msgtype'] as String?)?.trim();

    final sourceFuture = _loadPrivateReplySourceEvent(
      event,
      sourceRoomId: sourceRoomId,
      sourceEventId: sourceEventId,
    );

    return FutureBuilder<Event?>(
      future: sourceFuture,
      builder: (context, snapshot) {
        final sourceEvent = snapshot.data;
        final displayPreview = sourceEvent == null
            ? (preview?.isNotEmpty == true ? preview! : 'Original message')
            : _privateReplyPreviewText(
                sourceEvent,
                fallback: preview ?? 'Original message',
              );

        final canOpenSource = sourceRoomId?.isNotEmpty == true &&
            sourceEventId?.isNotEmpty == true &&
            onTap != null;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canOpenSource
              ? () => onTap!(sourceRoomId!, sourceEventId!)
              : null,
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
                _PrivateReplyMediaPreview(
                  event: sourceEvent,
                  fallbackMsgtype: msgtype ?? '',
                  isMe: isMe,
                  loadImageBytes: loadImageBytes,
                  loadVideoThumbnail: loadVideoThumbnail,
                ),
                if (_privateReplyHasMediaPreview(sourceEvent, msgtype ?? ''))
                  const SizedBox(width: 7),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sender?.isNotEmpty == true ? sender! : 'Message',
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
                        displayPreview,
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

  Future<Event?> _loadPrivateReplySourceEvent(
    Event privateReplyEvent, {
    required String? sourceRoomId,
    required String? sourceEventId,
  }) {
    if (sourceRoomId == null ||
        sourceRoomId.isEmpty ||
        sourceEventId == null ||
        sourceEventId.isEmpty) {
      return Future<Event?>.value(null);
    }

    final sourceRoom = privateReplyEvent.room.client.getRoomById(sourceRoomId);
    if (sourceRoom == null) return Future<Event?>.value(null);
    return _cachedReplyPreviewEvent(sourceRoom, sourceEventId);
  }

  String _privateReplyPreviewText(Event event, {required String fallback}) {
    switch (event.messageType) {
      case MessageTypes.Image:
        return 'Photo';
      case MessageTypes.Video:
        return 'Video';
      case MessageTypes.Audio:
        return 'Audio';
      case MessageTypes.File:
        return event.body.trim().isEmpty ? 'File' : event.body.trim();
      default:
        return fallback.trim().isEmpty ? 'Original message' : fallback.trim();
    }
  }
}

bool _privateReplyHasMediaPreview(Event? event, String fallbackMsgtype) {
  final msgtype = event?.messageType ?? fallbackMsgtype;
  return msgtype == MessageTypes.Image ||
      msgtype == MessageTypes.Video ||
      msgtype == MessageTypes.Audio ||
      msgtype == MessageTypes.File;
}

class _PrivateReplyMediaPreview extends StatelessWidget {
  final Event? event;
  final String fallbackMsgtype;
  final bool isMe;
  final Future<Uint8List?> Function(Event, {bool getThumbnail})? loadImageBytes;
  final Future<Uint8List?> Function(Event)? loadVideoThumbnail;

  const _PrivateReplyMediaPreview({
    required this.event,
    required this.fallbackMsgtype,
    required this.isMe,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
  });

  @override
  Widget build(BuildContext context) {
    final msgtype = event?.messageType ?? fallbackMsgtype;
    if (msgtype == MessageTypes.Image || msgtype == MessageTypes.Video) {
      final source = event;
      final isImage = msgtype == MessageTypes.Image;
      final cachedBytes = source == null
          ? null
          : _cachedReplyPreviewMediaBytes(source, isImage);
      final thumbFuture = source == null || cachedBytes != null
          ? null
          : _cachedReplyPreviewMediaFuture(
              source,
              isImage,
              loadImageBytes,
              loadVideoThumbnail,
            );

      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1A2A1A) : kDarkGrey,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<Uint8List?>(
          initialData: cachedBytes,
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
                    errorBuilder: (_, __, ___) => _PrivateReplyTypeIcon(
                      msgtype: msgtype,
                      isMe: isMe,
                    ),
                  ),
                  if (msgtype == MessageTypes.Video)
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
            return _PrivateReplyTypeIcon(msgtype: msgtype, isMe: isMe);
          },
        ),
      );
    }

    if (msgtype == MessageTypes.Audio || msgtype == MessageTypes.File) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1A2A1A) : kDarkGrey,
          borderRadius: BorderRadius.circular(10),
        ),
        child: _PrivateReplyTypeIcon(msgtype: msgtype, isMe: isMe),
      );
    }

    return const SizedBox.shrink();
  }
}

class _PrivateReplyTypeIcon extends StatelessWidget {
  final String msgtype;
  final bool isMe;

  const _PrivateReplyTypeIcon({
    required this.msgtype,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (msgtype) {
      MessageTypes.Image => Icons.image_rounded,
      MessageTypes.Video => Icons.play_arrow_rounded,
      MessageTypes.Audio => Icons.headphones_rounded,
      MessageTypes.File => Icons.insert_drive_file_rounded,
      _ => Icons.chat_bubble_rounded,
    };

    return Icon(
      icon,
      color: isMe ? kLimeGreen : kLightGrey,
      size: 20,
    );
  }
}

const _storyReplyContentKey = 'com.xmo.story_reply';

_StoryReplyContent? _storyReplyContent(Event event) {
  final raw = event.content[_storyReplyContentKey];
  if (raw is Map) {
    return _StoryReplyContent.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
  if (event.body.startsWith('Replied to your story\n')) {
    return const _StoryReplyContent.legacy();
  }
  return null;
}

String _storyReplyDisplayBody(
  String body,
  _StoryReplyContent? storyReply,
) {
  if (storyReply == null) return body;
  if (body.startsWith('Replied to your story\n')) {
    return body.substring('Replied to your story\n'.length).trim();
  }
  return body;
}

class _StoryReplyContent {
  final String? storyId;
  final String? storyOwnerId;
  final String? storyOwnerName;
  final String? mediaType;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? textContent;
  final String? caption;
  final DateTime? expiresAt;
  final bool legacy;

  const _StoryReplyContent({
    required this.storyId,
    required this.storyOwnerId,
    required this.storyOwnerName,
    required this.mediaType,
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.textContent,
    required this.caption,
    required this.expiresAt,
  }) : legacy = false;

  const _StoryReplyContent.legacy()
      : storyId = null,
        storyOwnerId = null,
        storyOwnerName = null,
        mediaType = null,
        mediaUrl = null,
        thumbnailUrl = null,
        textContent = null,
        caption = null,
        expiresAt = null,
        legacy = true;

  factory _StoryReplyContent.fromJson(Map<String, dynamic> json) {
    final expiresAtMs = json['expires_at'];
    return _StoryReplyContent(
      storyId: json['story_id'] as String?,
      storyOwnerId: json['story_owner_id'] as String?,
      storyOwnerName: json['story_owner_name'] as String?,
      mediaType: json['media_type'] as String?,
      mediaUrl: json['media_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      textContent: json['text_content'] as String?,
      caption: json['caption'] as String?,
      expiresAt: expiresAtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs)
          : null,
    );
  }

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && DateTime.now().isAfter(expiry);
  }

  String get previewText {
    if (isExpired) return 'Story expired';
    return '';
  }

  IconData get fallbackIcon {
    if (isExpired) return Icons.image_not_supported_outlined;
    return switch (mediaType) {
      'video' => Icons.play_arrow_rounded,
      'text' => Icons.text_fields_rounded,
      _ => Icons.image_outlined,
    };
  }

  String? get activeThumbnailUrl {
    if (isExpired) return null;
    return thumbnailUrl ?? mediaUrl;
  }
}

class _StoryReplyContextPreview extends StatelessWidget {
  final _StoryReplyContent? storyReply;
  final bool isMe;

  const _StoryReplyContextPreview({
    required this.storyReply,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final storyReply = this.storyReply;
    if (storyReply == null) return const SizedBox.shrink();

    final canOpen = _canOpenStory(context, storyReply);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canOpen ? () => _openStory(context, storyReply) : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 132),
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
              height: 38,
              decoration: BoxDecoration(
                color: isMe ? kLimeGreen : const Color(0xFF72B7F2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            _StoryReplyThumb(storyReply: storyReply, isMe: isMe),
            const SizedBox(width: 7),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Story',
                    style: GoogleFonts.inter(
                      color: isMe ? kLimeGreen : const Color(0xFF72B7F2),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    storyReply.isExpired ? 'expired' : 'replied',
                    style: GoogleFonts.inter(
                      color: isMe ? kLimeGreen : const Color(0xFF72B7F2),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
  }

  bool _canOpenStory(BuildContext context, _StoryReplyContent storyReply) {
    if (storyReply.isExpired || storyReply.storyId == null) return false;
    final myUserId = context.read<MatrixProvider>().userId;
    if (storyReply.storyOwnerId != null &&
        storyReply.storyOwnerId != myUserId) {
      return false;
    }
    return context
        .read<StoryProvider>()
        .myStories
        .any((story) => story.id == storyReply.storyId && !story.isExpired);
  }

  void _openStory(BuildContext context, _StoryReplyContent storyReply) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          initialUserIndex: -1,
          allUserStories: const [],
          initialStoryId: storyReply.storyId,
        ),
      ),
    );
  }
}

class _StoryReplyThumb extends StatelessWidget {
  final _StoryReplyContent storyReply;
  final bool isMe;

  const _StoryReplyThumb({
    required this.storyReply,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final request = _mediaRequest(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1A2A1A) : kDarkGrey,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: request == null
          ? _StoryReplyThumbFallback(storyReply: storyReply, isMe: isMe)
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  request.uri.toString(),
                  headers: request.headers,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _StoryReplyThumbFallback(
                      storyReply: storyReply, isMe: isMe),
                ),
                if (storyReply.mediaType == 'video' && !storyReply.isExpired)
                  Container(
                    color: Colors.black.withValues(alpha: 0.18),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
              ],
            ),
    );
  }

  MatrixMediaRequest? _mediaRequest(BuildContext context) {
    final url = storyReply.activeThumbnailUrl;
    if (url == null || url.isEmpty) return null;
    return context.read<MatrixProvider>().service.getMediaRequest(url);
  }
}

class _StoryReplyThumbFallback extends StatelessWidget {
  final _StoryReplyContent storyReply;
  final bool isMe;

  const _StoryReplyThumbFallback({
    required this.storyReply,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      storyReply.fallbackIcon,
      color: isMe ? kLimeGreen : kLightGrey,
      size: 20,
    );
  }
}
