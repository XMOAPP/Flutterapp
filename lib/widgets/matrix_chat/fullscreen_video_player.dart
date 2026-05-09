import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../screens/web_download_stub.dart' if (dart.library.html) '../../screens/web_download.dart' as web_download;
import '../../screens/web_video_view_stub.dart' if (dart.library.html) '../../screens/web_video_view.dart' as web_video;

/// Fullscreen in-app video player with download functionality
class FullscreenVideoPlayer extends StatefulWidget {
  final Uint8List videoBytes;
  final String mimeType;
  final String title;

  const FullscreenVideoPlayer({
    super.key,
    required this.videoBytes,
    required this.mimeType,
    required this.title,
  });

  @override
  State<FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<FullscreenVideoPlayer> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'video_player_${DateTime.now().millisecondsSinceEpoch}';
    web_video.registerVideoView(_viewId, widget.videoBytes, widget.mimeType);
  }

  @override
  void dispose() {
    web_video.disposeVideoView(_viewId);
    super.dispose();
  }

  void _downloadVideo(BuildContext context) {
    final ext = widget.mimeType.split('/').last;
    final fileName = widget.title.endsWith('.$ext')
        ? widget.title
        : '${widget.title}.$ext';
    web_download.downloadFile(widget.videoBytes, fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloaded: $fileName'),
        backgroundColor: const Color(0xFF1A2A1A),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: kWhite),
        title: Text(
          widget.title,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: kWhite),
            onPressed: () => _downloadVideo(context),
          ),
        ],
      ),
      body: Center(
        child: web_video.createVideoView(
            widget.videoBytes, widget.mimeType, _viewId),
      ),
    );
  }
}
