import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../providers/matrix_provider.dart';
import '../../services/matrix_attachment_downloader.dart';
import '../../services/matrix_service.dart';
import '../../theme.dart';
import '../../utils/matrix_identity.dart';
import '../../utils/message_presentation.dart';
import '../../widgets/incoming_call_fullscreen_scope.dart';
import '../../widgets/matrix_chat/fullscreen_image_viewer.dart';
import '../../widgets/matrix_chat/fullscreen_video_player.dart';
import '../../widgets/story/story_avatar.dart';
import '../matrix_chat/message_bubble.dart';
import '../matrix_chat/chat_space_background.dart';
import '../matrix_chat/forward_message_sheet.dart';
import '../matrix_chat/media_handler.dart';
import '../matrix_chat_screen.dart';
import '../native_share_stub.dart'
    if (dart.library.io) '../native_share.dart'
    as native_share;

class SavedChatMessagesScreen extends StatefulWidget {
  final Room savedRoom;
  final Room sourceRoom;

  const SavedChatMessagesScreen({
    super.key,
    required this.savedRoom,
    required this.sourceRoom,
  });

  @override
  State<SavedChatMessagesScreen> createState() =>
      _SavedChatMessagesScreenState();
}

class _SavedChatMessagesScreenState extends State<SavedChatMessagesScreen> {
  static const MatrixAttachmentDownloader _attachmentDownloader =
      MatrixAttachmentDownloader();
  late MediaHandler _mediaHandler;
  final TextEditingController _searchController = TextEditingController();
  List<Event> _events = [];
  bool _loading = true;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _mediaHandler = MediaHandler(
      matrixProvider: matrixProvider,
      context: context,
    );
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mediaHandler.clearCache();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    try {
      final timeline = await widget.savedRoom.getTimeline();
      final events = timeline.events.where((event) {
        if (event.redacted) return false;
        if (event.type != EventTypes.Message &&
            event.type != EventTypes.Sticker) {
          return false;
        }
        final forwarded = event.content['xmo.forwarded'];
        return forwarded is Map && forwarded['room_id'] == widget.sourceRoom.id;
      }).toList()..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));

      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load saved messages: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Event> get _filteredEvents {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _events;
    return _events.where((event) {
      return matrixVisibleBody(event).toLowerCase().contains(query) ||
          MatrixIdentity.displayName(
            userId: event.senderId,
            candidate: event.senderFromMemoryOrFallback.displayName,
          ).toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final events = _filteredEvents;
    final sourceName = MatrixService.cleanName(
      MatrixService().getResolvedDisplayName(widget.sourceRoom),
    );
    final count = _events.length;

    return IncomingCallFullscreenScope(
      child: Scaffold(
        backgroundColor: kBlack,
        appBar: AppBar(
          backgroundColor: kBlack,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kWhite),
            onPressed: () => Navigator.pop(context),
          ),
          titleSpacing: 0,
          title: _searching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  cursorColor: kLimeGreen,
                  style: GoogleFonts.inter(color: kWhite, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search saved messages',
                    hintStyle: GoogleFonts.inter(color: kLightGrey),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                )
              : Row(
                  children: [
                    StoryAvatar(
                      userName: sourceName,
                      avatarUrl: widget.sourceRoom.avatar?.toString(),
                      size: 42,
                      fallbackIcon:
                          !MatrixService().isDirectRoom(widget.sourceRoom) &&
                              widget.sourceRoom.isChannel
                          ? Icons.campaign
                          : !MatrixService().isDirectRoom(widget.sourceRoom) &&
                                widget.sourceRoom.isGroup
                          ? Icons.group
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: kWhite,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '$count saved ${count == 1 ? 'message' : 'messages'}',
                            style: GoogleFonts.inter(
                              color: kLightGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              icon: Icon(
                _searching ? Icons.close : Icons.search,
                color: kWhite,
              ),
              onPressed: () {
                setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _query = '';
                    _searchController.clear();
                  }
                });
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: ChatSpaceBackground()),
            Column(
              children: [
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: kLimeGreen),
                        )
                      : events.isEmpty
                      ? Center(
                          child: Text(
                            _query.isEmpty
                                ? 'No saved messages from this chat'
                                : 'No saved messages found',
                            style: GoogleFonts.inter(
                              color: kLightGrey,
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final event = events[index];
                            return GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onLongPress: () =>
                                  _showSavedMessageOptions(event),
                              child: MessageBubble(
                                event: event,
                                myUserId:
                                    context.read<MatrixProvider>().userId ?? '',
                                loadImageBytes: _mediaHandler.loadImageBytes,
                                playVideo: _openVideo,
                                downloadAndOpenFile: _openFile,
                                shareAttachment: _shareAttachment,
                                openAttachmentExternally: _openFile,
                                downloadAttachment: _downloadAttachment,
                                openFullscreenImage: _openFullscreenImage,
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF2C2C2E),
                          foregroundColor: kWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        onPressed: _openSourceChat,
                        child: Text(
                          'Open Chat',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<MatrixFile> _downloadAttachment(Event event) {
    return _attachmentDownloader.download(
      event,
      downloadCallback: _mediaHandler.authenticatedDownload(),
    );
  }

  Future<void> _openVideo(Event event) async {
    final file = await _downloadAttachment(event);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPlayer(
          videoBytes: file.bytes,
          mimeType: file.mimeType,
          title: file.name,
        ),
      ),
    );
  }

  Future<void> _openFile(Event event) async {
    final file = await _downloadAttachment(event);
    if (!mounted) return;
    await native_share.openFile(file.bytes, file.name, mimeType: file.mimeType);
  }

  Future<void> _shareAttachment(Event event) async {
    final file = await _downloadAttachment(event);
    await native_share.shareFile(
      file.bytes,
      file.name,
      mimeType: file.mimeType,
    );
  }

  String? _copyableText(Event event) {
    if (event.redacted || event.type != EventTypes.Message) return null;
    if (event.messageType != MessageTypes.Text &&
        event.messageType != MessageTypes.Notice) {
      return null;
    }
    final text = matrixVisibleBody(event).trim();
    return text.isEmpty ? null : text;
  }

  void _showSavedMessageOptions(Event event) {
    final copyText = _copyableText(event);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kDarkerGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (copyText != null)
                ListTile(
                  leading: const Icon(Icons.copy, color: kLimeGreen),
                  title: Text('Copy', style: GoogleFonts.inter(color: kWhite)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyMessage(copyText);
                  },
                ),
              ListTile(
                leading: Transform.scale(
                  scaleX: -1,
                  child: const Icon(Icons.reply, color: kLimeGreen),
                ),
                title: Text('Forward', style: GoogleFonts.inter(color: kWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  _forwardMessage(event);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  'Delete',
                  style: GoogleFonts.inter(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteSavedMessage(event);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), backgroundColor: kLimeGreen),
    );
  }

  Future<void> _forwardMessage(Event event) async {
    final matrixProvider = context.read<MatrixProvider>();
    final selectedRooms = await showForwardMessageSheet(
      context: context,
      rooms: matrixProvider.rooms,
      currentRoom: widget.savedRoom,
    );
    if (selectedRooms == null || selectedRooms.isEmpty) return;

    try {
      for (final room in selectedRooms) {
        await matrixProvider.service.forwardMessage(
          event: event,
          targetRoomId: room.id,
        );
      }
      if (!mounted) return;
      final count = selectedRooms.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Message forwarded'
                : 'Message forwarded to $count chats',
          ),
          backgroundColor: kLimeGreen,
        ),
      );
      matrixProvider.refreshRooms();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to forward message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteSavedMessage(Event event) async {
    try {
      await event.redactEvent();
      if (!mounted) return;
      setState(() {
        _events.removeWhere((item) => item.eventId == event.eventId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved message deleted'),
          backgroundColor: kLimeGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete saved message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openFullscreenImage(Uint8List bytes, String title, Event event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenImageViewer(
          imageBytes: bytes,
          title: title,
          event: event,
        ),
      ),
    );
  }

  Future<void> _openSourceChat() async {
    final matrixProvider = context.read<MatrixProvider>();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatrixChatScreen(
          room: widget.sourceRoom,
          matrixProvider: matrixProvider,
        ),
      ),
    );
    if (mounted) {
      await _loadEvents();
    }
  }
}
