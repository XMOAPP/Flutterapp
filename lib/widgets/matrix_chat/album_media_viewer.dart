import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../screens/native_share_stub.dart'
    if (dart.library.io) '../../screens/native_share.dart' as native_share;
import '../../screens/web_download_stub.dart'
    if (dart.library.js_interop) '../../screens/web_download.dart'
    as web_download;
import '../../theme.dart';

class AlbumMediaViewer extends StatefulWidget {
  final List<Event> events;
  final int initialIndex;
  final Future<Uint8List?> Function(Event event, {bool getThumbnail})
      loadImageBytes;
  final Future<Uint8List?> Function(Event event) loadVideoThumbnail;
  final Future<MatrixFile> Function(Event event) downloadAttachment;
  final Future<void> Function(Event event) playVideo;
  final Future<void> Function(Event event)? onReply;
  final Future<void> Function(Event event)? onDelete;
  final bool Function(Event event)? canDelete;

  const AlbumMediaViewer({
    super.key,
    required this.events,
    required this.initialIndex,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
    required this.downloadAttachment,
    required this.playVideo,
    this.onReply,
    this.onDelete,
    this.canDelete,
  });

  @override
  State<AlbumMediaViewer> createState() => _AlbumMediaViewerState();
}

class _AlbumMediaViewerState extends State<AlbumMediaViewer> {
  late final PageController _pageController;
  late int _index;
  bool _busy = false;

  Event get _currentEvent => widget.events[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.events.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _downloadCurrent() async {
    await _withBusy(() async {
      final file = await widget.downloadAttachment(_currentEvent);
      await web_download.downloadFile(
        file.bytes,
        file.name,
        mimeType: file.mimeType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Downloaded successfully'),
          backgroundColor: kLimeGreen,
          duration: Duration(seconds: 2),
        ),
      );
    }, errorPrefix: 'Failed to download');
  }

  Future<void> _shareCurrent() async {
    await _withBusy(() async {
      final file = await widget.downloadAttachment(_currentEvent);
      await native_share.shareFile(
        file.bytes,
        file.name,
        mimeType: file.mimeType,
      );
    }, errorPrefix: 'Failed to share');
  }

  Future<void> _withBusy(
    Future<void> Function() action, {
    required String errorPrefix,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$errorPrefix: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeAndRun(Future<void> Function(Event event)? action) async {
    if (action == null) return;
    final event = _currentEvent;
    Navigator.pop(context);
    await action(event);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.events.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final event = widget.events[index];
                return event.messageType == MessageTypes.Video
                    ? _AlbumVideoPage(
                        event: event,
                        loadVideoThumbnail: widget.loadVideoThumbnail,
                        playVideo: widget.playVideo,
                      )
                    : _AlbumImagePage(
                        event: event,
                        loadImageBytes: widget.loadImageBytes,
                      );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: kWhite, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              top: 17,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Text(
                  '${_index + 1} / ${widget.events.length}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: kWhite, size: 26),
                color: kDarkerGrey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (value) {
                  if (value == 'download') {
                    _downloadCurrent();
                  } else if (value == 'share') {
                    _shareCurrent();
                  } else if (value == 'reply') {
                    _closeAndRun(widget.onReply);
                  } else if (value == 'delete') {
                    _closeAndRun(widget.onDelete);
                  }
                },
                itemBuilder: (context) => [
                  _menuItem('download', Icons.download, 'Download'),
                  _menuItem('share', Icons.share, 'Share'),
                  if (widget.onReply != null)
                    _menuItem('reply', Icons.reply, 'Reply'),
                  if (widget.onDelete != null &&
                      (widget.canDelete?.call(_currentEvent) ?? false))
                    _menuItem(
                      'delete',
                      Icons.delete_outline,
                      'Delete',
                      color: Colors.red,
                    ),
                ],
              ),
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child: CircularProgressIndicator(color: kWhite),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color color = kWhite,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
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

class _AlbumImagePage extends StatelessWidget {
  final Event event;
  final Future<Uint8List?> Function(Event event, {bool getThumbnail})
      loadImageBytes;

  const _AlbumImagePage({
    required this.event,
    required this.loadImageBytes,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loadImageBytes(event),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: kWhite),
          );
        }
        return Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _AlbumError(
                icon: Icons.broken_image_outlined,
                label: 'Failed to load image',
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AlbumVideoPage extends StatelessWidget {
  final Event event;
  final Future<Uint8List?> Function(Event event) loadVideoThumbnail;
  final Future<void> Function(Event event) playVideo;

  const _AlbumVideoPage({
    required this.event,
    required this.loadVideoThumbnail,
    required this.playVideo,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loadVideoThumbnail(event),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => playVideo(event),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bytes != null && bytes.isNotEmpty)
                Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _AlbumVideoFallback(),
                )
              else
                const _AlbumVideoFallback(),
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: kWhite,
                    size: 44,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AlbumVideoFallback extends StatelessWidget {
  const _AlbumVideoFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.videocam, color: kLightGrey, size: 56),
    );
  }
}

class _AlbumError extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AlbumError({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kLightGrey, size: 64),
        const SizedBox(height: 12),
        Text(label, style: GoogleFonts.inter(color: kLightGrey)),
      ],
    );
  }
}
