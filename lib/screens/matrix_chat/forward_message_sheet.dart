import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../models/xmo_contact_card.dart';
import '../../providers/matrix_provider.dart';
import '../../services/matrix_service.dart';
import '../../theme.dart';
import '../../utils/message_presentation.dart';
import '../../widgets/story/story_avatar.dart';
import 'media_handler.dart';
import 'widgets/tappable_file_chip.dart';

/// Opens the forwarding destination picker.
///
/// The entry point intentionally keeps its original name so every existing
/// share and message-forward action continues to use the same contract.
Future<List<Room>?> showForwardMessageSheet({
  required BuildContext context,
  required List<Room> rooms,
  required Room currentRoom,
  String title = 'Forward to',
  String actionLabel = 'Forward',
  String emptyLabel = 'No chats available',
  List<Event> previewEvents = const <Event>[],
  String? previewLabel,
  IconData? previewIcon,
}) {
  final matrixService = MatrixService();
  final eligibleRooms =
      rooms.where((room) {
        return room.membership == Membership.join &&
            room.canSendEvent(EventTypes.Message);
      }).toList()..sort((a, b) {
        final aTime = a.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
        final bTime = b.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

  return Navigator.of(context).push<List<Room>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ForwardDestinationScreen(
        rooms: eligibleRooms,
        currentRoom: currentRoom,
        matrixService: matrixService,
        title: title,
        actionLabel: actionLabel,
        emptyLabel: emptyLabel,
        previewEvents: previewEvents,
        previewLabel: previewLabel,
        previewIcon: previewIcon,
      ),
    ),
  );
}

class _ForwardDestinationScreen extends StatefulWidget {
  final List<Room> rooms;
  final Room currentRoom;
  final MatrixService matrixService;
  final String title;
  final String actionLabel;
  final String emptyLabel;
  final List<Event> previewEvents;
  final String? previewLabel;
  final IconData? previewIcon;

  const _ForwardDestinationScreen({
    required this.rooms,
    required this.currentRoom,
    required this.matrixService,
    required this.title,
    required this.actionLabel,
    required this.emptyLabel,
    required this.previewEvents,
    this.previewLabel,
    this.previewIcon,
  });

  @override
  State<_ForwardDestinationScreen> createState() =>
      _ForwardDestinationScreenState();
}

class _ForwardDestinationScreenState extends State<_ForwardDestinationScreen> {
  final Set<String> _selectedRoomIds = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filteredRooms = widget.rooms
        .where((room) {
          if (normalizedQuery.isEmpty) return true;
          final name = widget.matrixService.getResolvedDisplayName(room);
          return name.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);

    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: kWhite),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_selectedRoomIds.isNotEmpty)
              Text(
                '${_selectedRoomIds.length} selected',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
              ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: TextField(
                autofocus: false,
                onChanged: (value) => setState(() => _query = value),
                style: GoogleFonts.inter(color: kWhite, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  hintStyle: GoogleFonts.inter(color: kLightGrey),
                  prefixIcon: const Icon(Icons.search, color: kLightGrey),
                  filled: true,
                  fillColor: kMediumGrey,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            Expanded(
              child: filteredRooms.isEmpty
                  ? Center(
                      child: Text(
                        widget.emptyLabel,
                        style: GoogleFonts.inter(
                          color: kLightGrey,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: filteredRooms.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final room = filteredRooms[index];
                        final isCurrentRoom = room.id == widget.currentRoom.id;
                        final selected = _selectedRoomIds.contains(room.id);
                        return _ForwardRoomTile(
                          room: room,
                          selected: selected,
                          isCurrentRoom: isCurrentRoom,
                          matrixService: widget.matrixService,
                          onTap: isCurrentRoom
                              ? null
                              : () {
                                  setState(() {
                                    if (selected) {
                                      _selectedRoomIds.remove(room.id);
                                    } else {
                                      _selectedRoomIds.add(room.id);
                                    }
                                  });
                                },
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.previewEvents.isNotEmpty ||
                      widget.previewLabel != null) ...[
                    _ForwardContentPreview(
                      events: widget.previewEvents,
                      fallbackLabel: widget.previewLabel,
                      fallbackIcon: widget.previewIcon,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedRoomIds.isEmpty
                                ? 'Select chat'
                                : _selectedDestinationLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: _selectedRoomIds.isEmpty
                                  ? kLightGrey
                                  : kWhite,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_selectedRoomIds.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 52,
                            height: 52,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: kLimeGreen,
                                foregroundColor: kBlack,
                                shape: const CircleBorder(),
                              ),
                              onPressed: () {
                                final selectedRooms = widget.rooms
                                    .where(
                                      (room) =>
                                          _selectedRoomIds.contains(room.id),
                                    )
                                    .toList(growable: false);
                                Navigator.of(context).pop(selectedRooms);
                              },
                              child: const Icon(Icons.send_rounded, size: 22),
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
      ),
    );
  }

  String _selectedDestinationLabel() {
    final names = widget.rooms
        .where((room) => _selectedRoomIds.contains(room.id))
        .map(widget.matrixService.getResolvedDisplayName)
        .map(MatrixService.cleanName)
        .toList(growable: false);
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names.first}, ${names.last}';
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }
}

class _ForwardContentPreview extends StatelessWidget {
  final List<Event> events;
  final String? fallbackLabel;
  final IconData? fallbackIcon;

  const _ForwardContentPreview({
    required this.events,
    this.fallbackLabel,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final details = _details();
    return Container(
      width: double.infinity,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: kMediumGrey,
        borderRadius: BorderRadius.zero,
        border: Border(left: BorderSide(color: kLimeGreen, width: 3)),
      ),
      child: Row(
        children: [
          if (_showsLeading()) ...[
            _ForwardPreviewLeading(
              event: _singleMediaEvent(),
              details: details,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              details.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  _ForwardPreviewDetails _details() {
    if (events.length > 1) {
      return _ForwardPreviewDetails(
        Icons.forward_to_inbox_rounded,
        '${events.length} messages',
      );
    }
    if (events.isEmpty) {
      return _ForwardPreviewDetails(
        fallbackIcon ?? Icons.person_rounded,
        fallbackLabel ?? 'Contact',
      );
    }

    final event = events.single;
    final contact = XmoContactCard.fromEventContent(
      Map<String, dynamic>.from(event.content),
    );
    if (contact != null) {
      return _ForwardPreviewDetails(Icons.person_rounded, contact.displayLabel);
    }

    final body = matrixVisibleBody(event, fallback: 'Message');
    switch (event.messageType) {
      case MessageTypes.Image:
        return _ForwardPreviewDetails(
          Icons.image_rounded,
          body == 'Message' ? 'Photo' : body,
        );
      case MessageTypes.Video:
        return _ForwardPreviewDetails(
          Icons.play_circle_rounded,
          body == 'Message' ? 'Video' : body,
        );
      case MessageTypes.Audio:
        return _ForwardPreviewDetails(
          Icons.graphic_eq_rounded,
          body == 'Message' ? 'Audio' : body,
        );
      case MessageTypes.File:
        return _ForwardPreviewDetails(
          Icons.insert_drive_file_rounded,
          body == 'Message' ? 'File' : body,
        );
      default:
        final isLink = RegExp(
          r'https?://',
          caseSensitive: false,
        ).hasMatch(body);
        return _ForwardPreviewDetails(
          isLink ? Icons.link_rounded : Icons.chat_bubble_outline_rounded,
          body,
        );
    }
  }

  Event? _singleMediaEvent() {
    if (events.length != 1) return null;
    final event = events.single;
    return event.messageType == MessageTypes.Image ||
            event.messageType == MessageTypes.Video
        ? event
        : null;
  }

  bool _showsLeading() {
    if (events.isEmpty || events.length > 1) return true;
    final event = events.single;
    if (event.messageType == MessageTypes.Image ||
        event.messageType == MessageTypes.Video ||
        event.messageType == MessageTypes.Audio ||
        event.messageType == MessageTypes.File) {
      return true;
    }
    return XmoContactCard.fromEventContent(
          Map<String, dynamic>.from(event.content),
        ) !=
        null;
  }
}

class _ForwardPreviewLeading extends StatelessWidget {
  final Event? event;
  final _ForwardPreviewDetails details;

  const _ForwardPreviewLeading({required this.event, required this.details});

  @override
  Widget build(BuildContext context) {
    final source = event;
    if (source == null) {
      return Icon(details.icon, color: kLimeGreen, size: 22);
    }
    return _ForwardMediaThumbnail(
      event: source,
      fallbackIcon: details.icon,
      size: 22,
    );
  }
}

class _ForwardMediaThumbnail extends StatefulWidget {
  final Event event;
  final IconData fallbackIcon;
  final double size;

  const _ForwardMediaThumbnail({
    super.key,
    required this.event,
    required this.fallbackIcon,
    this.size = 42,
  });

  @override
  State<_ForwardMediaThumbnail> createState() => _ForwardMediaThumbnailState();
}

class _ForwardMediaThumbnailState extends State<_ForwardMediaThumbnail> {
  late Future<Uint8List?> _thumbnailFuture;

  bool get _isVideo => widget.event.messageType == MessageTypes.Video;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _ForwardMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId) {
      _thumbnailFuture = _loadThumbnail();
    }
  }

  Uint8List? _cachedThumbnail() {
    return _isVideo
        ? MediaHandler.getCachedThumbnail(widget.event.eventId)
        : MediaHandler.getCachedImageBytes(
            widget.event.eventId,
            getThumbnail: true,
          );
  }

  Future<Uint8List?> _loadThumbnail() {
    final mediaHandler = MediaHandler(
      matrixProvider: context.read<MatrixProvider>(),
      context: context,
    );
    return _isVideo
        ? mediaHandler.loadVideoThumbnail(widget.event)
        : mediaHandler.loadImageBytes(widget.event, getThumbnail: true);
  }

  @override
  Widget build(BuildContext context) {
    final cachedBytes = _cachedThumbnail();
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size <= 24 ? 3 : 6),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FutureBuilder<Uint8List?>(
          initialData: cachedBytes,
          future: cachedBytes == null ? _thumbnailFuture : null,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) {
              return _ForwardThumbnailFallback(
                icon: widget.fallbackIcon,
                size: widget.size,
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: (widget.size * 2).round(),
                  cacheHeight: (widget.size * 2).round(),
                  errorBuilder: (_, __, ___) => _ForwardThumbnailFallback(
                    icon: widget.fallbackIcon,
                    size: widget.size,
                  ),
                ),
                if (_isVideo)
                  Container(
                    color: Colors.black.withValues(alpha: 0.22),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: kWhite,
                      size: widget.size <= 24 ? 15 : 23,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ForwardThumbnailFallback extends StatelessWidget {
  final IconData icon;
  final double size;

  const _ForwardThumbnailFallback({required this.icon, required this.size});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kDarkerGrey,
      child: Icon(icon, color: kLimeGreen, size: size * 0.52),
    );
  }
}

class _ForwardPreviewDetails {
  final IconData icon;
  final String label;

  const _ForwardPreviewDetails(this.icon, this.label);
}

class _ForwardRoomTile extends StatelessWidget {
  final Room room;
  final bool selected;
  final bool isCurrentRoom;
  final MatrixService matrixService;
  final VoidCallback? onTap;

  const _ForwardRoomTile({
    required this.room,
    required this.selected,
    required this.isCurrentRoom,
    required this.matrixService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDirect = matrixService.isDirectRoom(room);
    final isSavedMessages = matrixService.isSavedMessagesRoom(room);
    final name = MatrixService.cleanName(
      matrixService.getResolvedDisplayName(room),
    );
    final fallbackSubtitle = isDirect
        ? 'Direct chat'
        : room.isChannel
        ? 'Channel'
        : 'Group';
    final lastEvent = room.lastEvent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: isCurrentRoom ? 0.55 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                StoryAvatar(
                  userName: name,
                  avatarUrl: room.avatar?.toString(),
                  size: 48,
                  fallbackIcon: !isDirect && room.isChannel
                      ? Icons.campaign_rounded
                      : !isDirect && room.isGroup
                      ? Icons.group_rounded
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: kWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!isSavedMessages) ...[
                        const SizedBox(height: 3),
                        _ForwardRoomMessagePreview(
                          event: isCurrentRoom ? null : lastEvent,
                          fallback: isCurrentRoom
                              ? 'Current chat'
                              : fallbackSubtitle,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? kLimeGreen : kMediumGrey,
                  size: 27,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ForwardRoomMessagePreview extends StatelessWidget {
  final Event? event;
  final String fallback;

  const _ForwardRoomMessagePreview({
    required this.event,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final preview = _ForwardRoomPreviewData.fromEvent(
      event,
      fallback: fallback,
    );
    final text = Text(
      preview.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        color: preview.accentText ? kAudioBlue : kLightGrey,
        fontSize: 13,
      ),
    );
    if (!preview.hasVisual) return text;

    return Row(
      children: [
        if (preview.mediaEvent != null)
          _ForwardMediaThumbnail(
            key: ValueKey(preview.mediaEvent!.eventId),
            event: preview.mediaEvent!,
            fallbackIcon: preview.icon ?? Icons.image_rounded,
            size: 20,
          )
        else
          Icon(preview.icon, color: preview.iconColor, size: 17),
        const SizedBox(width: 5),
        Expanded(child: text),
      ],
    );
  }
}

class _ForwardRoomPreviewData {
  final String text;
  final IconData? icon;
  final Color iconColor;
  final Event? mediaEvent;
  final bool accentText;

  const _ForwardRoomPreviewData({
    required this.text,
    this.icon,
    this.iconColor = kLightGrey,
    this.mediaEvent,
    this.accentText = false,
  });

  bool get hasVisual => icon != null || mediaEvent != null;

  factory _ForwardRoomPreviewData.fromEvent(
    Event? event, {
    required String fallback,
  }) {
    if (event == null) return _ForwardRoomPreviewData(text: fallback);
    if (event.redacted) {
      return const _ForwardRoomPreviewData(
        text: 'Deleted message',
        icon: Icons.block_rounded,
      );
    }
    if (event.type == EventTypes.Encrypted) {
      return const _ForwardRoomPreviewData(
        text: 'Encrypted message',
        icon: Icons.lock_rounded,
      );
    }
    if (event.type == 'm.room.member') {
      return const _ForwardRoomPreviewData(
        text: 'Room created',
        icon: Icons.group_add_rounded,
      );
    }
    if (event.type != EventTypes.Message) {
      return _ForwardRoomPreviewData(
        text: matrixVisibleBody(event, fallback: fallback),
      );
    }

    final contact = XmoContactCard.fromEventContent(
      Map<String, dynamic>.from(event.content),
    );
    if (contact != null) {
      return _ForwardRoomPreviewData(
        text: contact.displayLabel,
        icon: Icons.person_rounded,
      );
    }

    switch (event.messageType) {
      case MessageTypes.Image:
        return _ForwardRoomPreviewData(
          text: _captionOrLabel(event, 'Photo'),
          icon: Icons.image_rounded,
          iconColor: kAudioBlue,
          mediaEvent: event,
          accentText: true,
        );
      case MessageTypes.Video:
        return _ForwardRoomPreviewData(
          text: _captionOrLabel(event, 'Video'),
          icon: Icons.videocam_rounded,
          iconColor: kAudioBlue,
          mediaEvent: event,
          accentText: true,
        );
      case MessageTypes.Audio:
        return _ForwardRoomPreviewData(
          text: matrixAttachmentFileName(event, fallback: 'Audio'),
          icon: Icons.headphones_rounded,
          accentText: true,
        );
      case MessageTypes.File:
        final attachmentType = detectAttachmentType(event);
        return _ForwardRoomPreviewData(
          text: matrixAttachmentFileName(event, fallback: 'File'),
          icon: attachmentType.icon,
        );
      default:
        return _ForwardRoomPreviewData(
          text: matrixVisibleBody(event, fallback: fallback),
        );
    }
  }

  static String _captionOrLabel(Event event, String fallback) {
    final caption = event.content['xmo_caption']?.toString().trim();
    return caption == null || caption.isEmpty ? fallback : caption;
  }
}
