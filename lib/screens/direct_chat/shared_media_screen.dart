import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/direct_chat_service.dart';
import '../../models/direct_chat_models.dart';
import '../../widgets/matrix_chat/fullscreen_image_viewer.dart';
import '../../widgets/matrix_chat/fullscreen_video_player.dart';
import '../matrix_chat/media_handler.dart';
import '../web_download_stub.dart' if (dart.library.js_interop) '../web_download.dart'
    as web_download;

/// Shared Media Screen - Shows all media shared in direct chat
class SharedMediaScreen extends StatefulWidget {
  final Room room;

  const SharedMediaScreen({
    super.key,
    required this.room,
  });

  @override
  State<SharedMediaScreen> createState() => _SharedMediaScreenState();
}

class _SharedMediaScreenState extends State<SharedMediaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DirectChatService _directChatService;
  
  List<SharedMediaItem> _photos = [];
  List<SharedMediaItem> _videos = [];
  List<SharedMediaItem> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final matrixProvider = context.read<MatrixProvider>();
    _directChatService = DirectChatService(matrixProvider.service);
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() => _loading = true);
    try {
      final media = await _directChatService.getSharedMedia(widget.room.id);
      
      if (mounted) {
        setState(() {
          _photos = media.where((m) => m.type == MediaType.image).toList();
          _videos = media.where((m) => m.type == MediaType.video).toList();
          _files = media.where((m) => 
            m.type == MediaType.file || m.type == MediaType.audio
          ).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[SharedMedia] Error loading media: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: kLimeGreen,
          labelColor: kLimeGreen,
          unselectedLabelColor: kLightGrey,
          labelStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(text: 'Photos (${_photos.length})'),
            Tab(text: 'Videos (${_videos.length})'),
            Tab(text: 'Files (${_files.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMediaGrid(_photos),
                _buildMediaGrid(_videos),
                _buildFilesList(_files),
              ],
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
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
            // Placeholder icon
            Center(
              child: Icon(
                item.type == MediaType.image
                    ? Icons.image
                    : Icons.videocam,
                color: kLimeGreen,
                size: 32,
              ),
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
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildFileTile(items[i]),
    );
  }

  Widget _buildFileTile(SharedMediaItem item) {
    final sizeStr = item.fileSize != null
        ? _formatFileSize(item.fileSize!)
        : 'Unknown size';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kLimeGreen.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            item.type == MediaType.audio
                ? Icons.audiotrack
                : Icons.insert_drive_file,
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
        subtitle: Text(
          sizeStr,
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 12,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download, color: kLimeGreen),
          onPressed: () => _downloadFile(item),
        ),
        onTap: () => _openMedia(item),
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
      } else {
        await _downloadFile(item);
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

  Future<void> _downloadFile(SharedMediaItem item) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${item.filename}...'),
          backgroundColor: kDarkerGrey,
          duration: const Duration(seconds: 2),
        ),
      );

      final event = await _findEvent(item.eventId);
      if (event == null) throw Exception('Message not found');

      final matrixFile = await _downloadMatrixFile(event);
      await web_download.downloadFile(matrixFile.bytes, matrixFile.name);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kIsWeb
              ? 'Downloaded: ${matrixFile.name}'
              : 'Downloaded successfully'),
          backgroundColor: const Color(0xFF1A2A1A),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Event?> _findEvent(String eventId) async {
    final timeline = await widget.room.getTimeline();
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
    return event.downloadAndDecryptAttachment(
      downloadCallback: mediaHandler.authenticatedDownload(),
    );
  }
}
