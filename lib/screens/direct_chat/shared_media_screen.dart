import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/matrix_attachment_downloader.dart';
import '../../services/matrix_service.dart';
import '../../services/shared_media_index_service.dart';
import '../../models/direct_chat_models.dart';
import '../../widgets/incoming_call_fullscreen_scope.dart';
import '../../widgets/matrix_chat/fullscreen_image_viewer.dart';
import '../../widgets/matrix_chat/fullscreen_video_player.dart';
import '../../widgets/story/story_avatar.dart';
import '../home/matrix_room_tile.dart';
import '../matrix_chat/media_handler.dart';
import '../matrix_chat/widgets/tappable_file_chip.dart';
import '../native_share_stub.dart' if (dart.library.io) '../native_share.dart'
    as native_share;
import 'saved_chat_messages_screen.dart';

/// Shared Media Screen - Shows all media shared in direct chat
class SharedMediaScreen extends StatefulWidget {
  final Room room;
  final bool embedded;
  final bool showTitle;
  final bool showDivider;
  final double height;

  const SharedMediaScreen({
    super.key,
    required this.room,
    this.embedded = false,
    this.showTitle = false,
    this.showDivider = true,
    this.height = 520,
  });

  @override
  State<SharedMediaScreen> createState() => _SharedMediaScreenState();
}

class _SharedMediaScreenState extends State<SharedMediaScreen>
    with SingleTickerProviderStateMixin {
  static const MatrixAttachmentDownloader _attachmentDownloader =
      MatrixAttachmentDownloader();
  late TabController _tabController;
  late MediaHandler _mediaHandler;
  final SharedMediaIndexService _indexService =
      SharedMediaIndexService.instance;
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  bool get _showChatTab =>
      context.read<MatrixProvider>().service.isSavedMessagesRoom(widget.room);

  List<SharedMediaItem> _photos = [];
  List<SharedMediaItem> _videos = [];
  List<SharedMediaItem> _audio = [];
  List<SharedMediaItem> _files = [];
  List<SharedMediaLinkItem> _links = [];
  List<Room> _chatRooms = [];
  Map<String, int> _savedCountsByRoomId = {};
  Timeline? _sharedTimeline;
  bool _loading = true;
  bool _indexingHistory = false;
  String? _mediaIndexRunId;
  String? _mediaIndexOwnerUserId;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    final showChatTab = matrixProvider.service.isSavedMessagesRoom(widget.room);
    _tabController = TabController(length: showChatTab ? 6 : 5, vsync: this);
    _mediaHandler = MediaHandler(
      matrixProvider: matrixProvider,
      context: context,
    );
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() {
      _loading = true;
      _indexingHistory = false;
    });
    try {
      final matrixProvider = context.read<MatrixProvider>();
      final ownerUserId = matrixProvider.userId;
      if (ownerUserId == null || ownerUserId.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final cached = await _indexService.read(
        ownerUserId: ownerUserId,
        roomId: widget.room.id,
      );
      _applyIndexSnapshot(cached);

      final timeline = await widget.room.getTimeline();
      _sharedTimeline = timeline;
      final chatRooms = _loadChatRooms(timeline);
      var snapshot = await _indexService.indexTimeline(
        ownerUserId: ownerUserId,
        room: widget.room,
        timeline: timeline,
        historyComplete: !timeline.canRequestHistory,
      );

      if (mounted) {
        setState(() {
          _chatRooms = chatRooms;
          _savedCountsByRoomId = _pendingSavedCountsByRoomId;
          _photos = snapshot.photos;
          _videos = snapshot.videos;
          _audio = snapshot.audio;
          _files = snapshot.files;
          _links = snapshot.links;
          _loading = false;
          _indexingHistory = !snapshot.historyComplete;
        });
      }

      if (!snapshot.historyComplete && timeline.canRequestHistory) {
        final runId =
            '$ownerUserId:${widget.room.id}:${DateTime.now().microsecondsSinceEpoch}';
        _mediaIndexOwnerUserId = ownerUserId;
        _mediaIndexRunId = runId;
        unawaited(_continueHistoryIndexing(
          ownerUserId: ownerUserId,
          timeline: timeline,
          runId: runId,
        ));
      }
    } catch (e) {
      debugPrint('[SharedMedia] Error loading media: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _indexingHistory = false;
        });
      }
    }
  }

  void _applyIndexSnapshot(SharedMediaIndexSnapshot snapshot) {
    if (!mounted) return;
    setState(() {
      _photos = snapshot.photos;
      _videos = snapshot.videos;
      _audio = snapshot.audio;
      _files = snapshot.files;
      _links = snapshot.links;
      _loading = false;
      _indexingHistory = !snapshot.historyComplete;
    });
  }

  @override
  void dispose() {
    final ownerUserId = _mediaIndexOwnerUserId;
    if (ownerUserId != null && ownerUserId.isNotEmpty) {
      _indexService.cancelHistoryIndex(
        ownerUserId: ownerUserId,
        roomId: widget.room.id,
        runId: _mediaIndexRunId,
      );
    }
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _continueHistoryIndexing({
    required String ownerUserId,
    required Timeline timeline,
    required String runId,
  }) async {
    try {
      while (mounted && _mediaIndexRunId == runId) {
        final progress = await _indexService.indexNextHistoryBatch(
          ownerUserId: ownerUserId,
          room: widget.room,
          timeline: timeline,
          pageSize: 100,
          maxPages: 2,
          runId: runId,
          onSnapshot: _applyIndexSnapshot,
        );
        if (progress.cancelled || progress.snapshot.historyComplete) break;
        // Keep this cooperative: rendering and navigation stay responsive even
        // for rooms with years of media history.
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    } finally {
      if (mounted && _mediaIndexRunId == runId) {
        setState(() => _indexingHistory = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return SizedBox(
        height: widget.height,
        child: _buildPanel(showTitle: widget.showTitle),
      );
    }

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
          title: Text(
            'Shared Media',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: _buildPanel(),
      ),
    );
  }

  Map<String, int> _pendingSavedCountsByRoomId = {};

  Widget _buildPanel({bool showTitle = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Text(
              'Shared Media',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        TabBar(
          controller: _tabController,
          labelPadding: EdgeInsets.zero,
          indicatorColor: kLimeGreen,
          dividerColor: Colors.transparent,
          labelColor: kLimeGreen,
          unselectedLabelColor: kLightGrey,
          labelStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            if (_showChatTab) const Tab(text: 'Chat'),
            const Tab(text: 'Photos'),
            const Tab(text: 'Videos'),
            const Tab(text: 'Audio'),
            const Tab(text: 'Files'),
            const Tab(text: 'Links'),
          ],
        ),
        if (widget.showDivider) const Divider(color: kWhite, height: 1),
        if (_indexingHistory)
          const LinearProgressIndicator(
            minHeight: 2,
            color: kLimeGreen,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: kLimeGreen))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    if (_showChatTab) _buildChatTab(),
                    _buildMediaGrid(_photos),
                    _buildMediaGrid(_videos),
                    _buildAudioList(_audio),
                    _buildFilesList(_files),
                    _buildLinksList(_links),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildChatTab() {
    if (_chatRooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              color: kMediumGrey,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No chats yet',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: _chatRooms
          .map(
            (room) => MatrixService().isSavedMessagesRoom(widget.room)
                ? _SavedSourceRoomTile(
                    room: room,
                    savedCount: _savedCountsByRoomId[room.id] ?? 0,
                    onTap: () => _openSavedSourceRoom(room),
                  )
                : MatrixRoomTile(
                    room: room,
                    showUnreadBadge: false,
                  ),
          )
          .toList(),
    );
  }

  void _openSavedSourceRoom(Room sourceRoom) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SavedChatMessagesScreen(
          savedRoom: widget.room,
          sourceRoom: sourceRoom,
        ),
      ),
    );
  }

  Widget _buildMediaGrid(List<SharedMediaItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              color: kMediumGrey,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No media shared yet',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildMediaTile(items[i]),
    );
  }

  Widget _buildMediaTile(SharedMediaItem item) {
    return GestureDetector(
      onTap: () => _openMedia(item),
      child: Container(
        decoration: BoxDecoration(
          color: kDarkerGrey,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _thumbnailFutureFor(item),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes != null && bytes.isNotEmpty) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  );
                }

                return Center(
                  child: Icon(
                    item.type == MediaType.image ? Icons.image : Icons.videocam,
                    color: kLimeGreen,
                    size: 32,
                  ),
                );
              },
            ),
            // Video indicator
            if (item.type == MediaType.video)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: kWhite,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesList(List<SharedMediaItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_outlined,
              color: kMediumGrey,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No files shared yet',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildFileTile(items[i]),
    );
  }

  Widget _buildAudioList(List<SharedMediaItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.audiotrack,
              color: kMediumGrey,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No audio shared yet',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: items.length,
      itemBuilder: (_, i) => _SharedAudioTile(
        item: items[i],
        downloadMatrixFile: _downloadMatrixFileForItem,
        formatFileSize: _formatFileSize,
      ),
    );
  }

  Widget _buildFileTile(SharedMediaItem item) {
    final sizeStr = item.fileSize != null
        ? _formatFileSize(item.fileSize!)
        : 'Unknown size';
    final attachmentType = attachmentTypeFor(
      mimeType: null,
      fileName: item.filename,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 0.5),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kLimeGreen.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            attachmentType.icon,
            color: kLimeGreen,
            size: 20,
          ),
        ),
        title: Text(
          item.filename,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$sizeStr • ',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 12,
              ),
            ),
            Text(
              attachmentType.label,
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        onTap: () => _openFile(item),
      ),
    );
  }

  Widget _buildLinksList(List<SharedMediaLinkItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.link,
              color: kMediumGrey,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No links shared yet',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildLinkTile(items[i]),
    );
  }

  Widget _buildLinkTile(SharedMediaLinkItem item) {
    final uri = _uriForLink(item.url);
    return Padding(
      padding: const EdgeInsets.only(bottom: 0.5),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kLimeGreen.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.link, color: kLimeGreen, size: 20),
        ),
        title: Text(
          uri?.host.isNotEmpty == true ? uri!.host : item.url,
          style: GoogleFonts.inter(
            color: kAudioBlue,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.url,
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _openLink(item.url),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _openMedia(SharedMediaItem item) async {
    try {
      final event = await _findEvent(item.eventId);
      if (event == null) throw Exception('Message not found');

      final matrixFile = await _downloadMatrixFile(event);
      if (!mounted) return;

      if (item.type == MediaType.image) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullscreenImageViewer(
              imageBytes: matrixFile.bytes,
              title: matrixFile.name,
              event: event,
            ),
          ),
        );
      } else if (item.type == MediaType.video) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullscreenVideoPlayer(
              videoBytes: matrixFile.bytes,
              mimeType: matrixFile.mimeType,
              title: matrixFile.name,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openFile(SharedMediaItem item) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening ${item.filename}...'),
          backgroundColor: kDarkerGrey,
          duration: const Duration(seconds: 2),
        ),
      );

      final event = await _findEvent(item.eventId);
      if (event == null) throw Exception('Message not found');

      final matrixFile = await _downloadMatrixFile(event);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (matrixFile.mimeType.startsWith('image/')) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullscreenImageViewer(
              imageBytes: matrixFile.bytes,
              title: matrixFile.name,
              event: event,
            ),
          ),
        );
        return;
      }

      if (matrixFile.mimeType.startsWith('video/')) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullscreenVideoPlayer(
              videoBytes: matrixFile.bytes,
              mimeType: matrixFile.mimeType,
              title: matrixFile.name,
            ),
          ),
        );
        return;
      }

      await native_share.openFile(
        matrixFile.bytes,
        matrixFile.name,
        mimeType: matrixFile.mimeType,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Room> _loadChatRooms(Timeline timeline) {
    final matrixProvider = context.read<MatrixProvider>();
    final matrixService = matrixProvider.service;

    if (!matrixService.isSavedMessagesRoom(widget.room)) {
      return [widget.room];
    }

    final roomIds = <String>{};
    final counts = <String, int>{};
    for (final event in timeline.events) {
      if (event.redacted) continue;
      final forwarded = event.content['xmo.forwarded'];
      if (forwarded is! Map) continue;
      final roomId = forwarded['room_id'];
      if (roomId is String && roomId.isNotEmpty) {
        roomIds.add(roomId);
        counts[roomId] = (counts[roomId] ?? 0) + 1;
      }
    }

    final rooms = <Room>[];
    for (final roomId in roomIds) {
      Room? room = matrixService.getRoomById(roomId);
      for (final candidate in matrixProvider.rooms) {
        if (candidate.id == roomId) {
          room = candidate;
          break;
        }
      }
      if (room != null) {
        rooms.add(room);
      }
    }
    _pendingSavedCountsByRoomId = counts;
    return rooms;
  }

  Future<void> _openLink(String url) async {
    final uri = _uriForLink(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication) ||
        await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!opened) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open link'),
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

  Future<Event?> _findEvent(String eventId) async {
    final timeline = _sharedTimeline ?? await widget.room.getTimeline();
    for (final event in timeline.events) {
      if (event.eventId == eventId) return event;
    }
    return widget.room.getEventById(eventId);
  }

  Future<MatrixFile> _downloadMatrixFile(Event event) {
    final matrixProvider = context.read<MatrixProvider>();
    final mediaHandler = MediaHandler(
      matrixProvider: matrixProvider,
      context: context,
    );
    return _attachmentDownloader.download(
      event,
      downloadCallback: mediaHandler.authenticatedDownload(),
    );
  }

  Future<MatrixFile> _downloadMatrixFileForItem(SharedMediaItem item) async {
    final event = await _findEvent(item.eventId);
    if (event == null) throw Exception('Message not found');
    return _downloadMatrixFile(event);
  }

  Future<Uint8List?> _thumbnailFutureFor(SharedMediaItem item) {
    return _thumbnailFutures.putIfAbsent(item.eventId, () async {
      final event = await _findEvent(item.eventId);
      if (event == null) return null;

      if (item.type == MediaType.image) {
        return _mediaHandler.loadImageBytes(event, getThumbnail: true);
      }
      if (item.type == MediaType.video) {
        return _mediaHandler.loadVideoThumbnail(event);
      }
      return null;
    });
  }
}

class _SavedSourceRoomTile extends StatelessWidget {
  final Room room;
  final int savedCount;
  final VoidCallback onTap;

  const _SavedSourceRoomTile({
    required this.room,
    required this.savedCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final matrixService = MatrixService();
    final isDirect = matrixService.isDirectRoom(room);
    final cleanedName =
        MatrixService.cleanName(matrixService.getResolvedDisplayName(room));
    final label =
        '$savedCount saved ${savedCount == 1 ? 'message' : 'messages'}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: StoryAvatar(
        userName: cleanedName,
        avatarUrl: room.avatar?.toString(),
        size: 50,
        fallbackIcon: !isDirect && room.isChannel
            ? Icons.campaign
            : !isDirect && room.isGroup
                ? Icons.group
                : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              cleanedName,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isDirect && (room.isChannel || room.isGroup)) ...[
            const SizedBox(width: 8),
            room.isChannel ? const ChannelBadge() : const GroupBadge(),
          ],
        ],
      ),
      subtitle: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: kLightGrey,
          fontSize: 13,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _SharedAudioTile extends StatefulWidget {
  final SharedMediaItem item;
  final Future<MatrixFile> Function(SharedMediaItem item) downloadMatrixFile;
  final String Function(int bytes) formatFileSize;

  const _SharedAudioTile({
    required this.item,
    required this.downloadMatrixFile,
    required this.formatFileSize,
  });

  @override
  State<_SharedAudioTile> createState() => _SharedAudioTileState();
}

class _SharedAudioTileState extends State<_SharedAudioTile> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  bool _ready = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
    });
    _positionSub = _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    _durationSub = _player.durationStream.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration ?? Duration.zero);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    try {
      if (!_ready) {
        setState(() => _loading = true);
        final matrixFile = await widget.downloadMatrixFile(widget.item);
        final uri = Uri.dataFromBytes(
          matrixFile.bytes,
          mimeType: matrixFile.mimeType,
        );
        await _player.setUrl(uri.toString());
        if (!mounted) return;
        setState(() {
          _ready = true;
          _loading = false;
        });
      }

      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not play audio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _seekToProgress(double value) async {
    if (!_ready || _duration <= Duration.zero) return;
    await _player.seek(
      Duration(milliseconds: (_duration.inMilliseconds * value).round()),
    );
  }

  Widget _buildProgressControl(double progress) {
    return SizedBox(
      height: 18,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        ),
        child: Slider(
          value: progress,
          min: 0,
          max: 1,
          activeColor: kLimeGreen,
          inactiveColor: kMediumGrey,
          onChanged: _ready && _duration > Duration.zero
              ? (value) => _seekToProgress(value)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sizeStr = widget.item.fileSize != null
        ? widget.formatFileSize(widget.item.fileSize!)
        : 'Unknown size';
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
        minLeadingWidth: 38,
        minVerticalPadding: 0,
        contentPadding: EdgeInsets.zero,
        leading: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 42, height: 42),
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: kLimeGreen,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: kLimeGreen,
                  size: 40,
                ),
          onPressed: _loading ? null : _togglePlayback,
        ),
        title: Text(
          widget.item.filename,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressControl(progress),
            Text(
              sizeStr,
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
