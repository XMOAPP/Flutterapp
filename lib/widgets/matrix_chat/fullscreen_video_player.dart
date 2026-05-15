import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';
import '../../theme.dart';
import '../../screens/web_download_stub.dart' if (dart.library.js_interop) '../../screens/web_download.dart' as web_download;
import '../../screens/web_video_view_stub.dart' if (dart.library.js_interop) '../../screens/web_video_view.dart' as web_video;
import '../../screens/native_share_stub.dart' if (dart.library.io) '../../screens/native_share.dart'
    as native_share;
import 'native_video_controller_stub.dart'
    if (dart.library.io) 'native_video_controller_io.dart';

/// Fullscreen in-app video player with download functionality
class FullscreenVideoPlayer extends StatefulWidget {
  final Uint8List? videoBytes;
  final String? mimeType;
  final String title;
  final Future<MatrixFile>? videoFuture;

  const FullscreenVideoPlayer({
    super.key,
    required this.videoBytes,
    required this.mimeType,
    required this.title,
  }) : videoFuture = null;

  const FullscreenVideoPlayer.loading({
    super.key,
    required this.videoFuture,
    required this.title,
  })  : videoBytes = null,
        mimeType = null;

  @override
  State<FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<FullscreenVideoPlayer> {
  late final String _viewId;
  VideoPlayerController? _nativeController;
  Future<void>? _nativeInit;
  Uint8List? _videoBytes;
  String? _mimeType;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewId = 'video_player_${DateTime.now().millisecondsSinceEpoch}';
    _videoBytes = widget.videoBytes;
    _mimeType = widget.mimeType;
    final future = widget.videoFuture;
    if (future != null) {
      _nativeInit = _loadAndInitVideo(future);
    } else {
      _nativeInit = _initLoadedVideo();
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      web_video.disposeVideoView(_viewId);
    }
    _nativeController?.dispose();
    super.dispose();
  }

  Future<void> _initNativeVideo() async {
    final bytes = _videoBytes;
    final mimeType = _mimeType;
    if (bytes == null || mimeType == null) return;
    final controller = await createNativeVideoController(
      bytes: bytes,
      mimeType: mimeType,
      title: widget.title,
    );
    if (!mounted) {
      await controller.dispose();
      return;
    }
    await controller.play();
    setState(() => _nativeController = controller);
  }

  Future<void> _loadAndInitVideo(Future<MatrixFile> future) async {
    try {
      final matrixFile = await future;
      if (!mounted) return;
      _videoBytes = matrixFile.bytes;
      _mimeType = matrixFile.mimeType;
      await _initLoadedVideo();
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load video: $e');
    }
  }

  Future<void> _initLoadedVideo() async {
    final bytes = _videoBytes;
    final mimeType = _mimeType;
    if (bytes == null || mimeType == null) return;
    if (kIsWeb) {
      web_video.registerVideoView(_viewId, bytes, mimeType);
    } else {
      await _initNativeVideo();
    }
  }

  Future<void> _downloadVideo(BuildContext context) async {
    final video = await _readyVideo(context);
    if (video == null) return;
    try {
      await web_download.downloadFile(
        video.bytes,
        video.fileName,
        mimeType: video.mimeType,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              kIsWeb ? 'Downloaded: ${video.fileName}' : 'Downloaded successfully'),
          backgroundColor: const Color(0xFF1A2A1A),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareVideo(BuildContext context) async {
    final video = await _readyVideo(context);
    if (video == null) return;
    try {
      await native_share.shareFile(
        video.bytes,
        video.fileName,
        mimeType: video.mimeType,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<_LoadedVideo?> _readyVideo(BuildContext context) async {
    if (_videoBytes == null || _mimeType == null) {
      try {
        await _nativeInit;
      } catch (_) {
        // The error is already displayed by the player body.
      }
    }

    final bytes = _videoBytes;
    final mimeType = _mimeType;
    if (bytes == null || mimeType == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video is still loading'),
            backgroundColor: kDarkerGrey,
          ),
        );
      }
      return null;
    }

    return _LoadedVideo(
      bytes: bytes,
      mimeType: mimeType,
      fileName: _videoFileName(mimeType),
    );
  }

  String _videoFileName(String mimeType) {
    final title = widget.title.trim().isEmpty ? 'xmo_video' : widget.title.trim();
    final dotIndex = title.lastIndexOf('.');
    if (dotIndex > 0 && dotIndex < title.length - 1) return title;

    final ext = switch (mimeType.toLowerCase()) {
      'video/mp4' => 'mp4',
      'video/quicktime' => 'mov',
      'video/webm' => 'webm',
      'video/x-matroska' => 'mkv',
      _ => mimeType.split('/').last,
    };
    return '$title.$ext';
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: kWhite),
            color: kDarkerGrey,
            onSelected: (value) {
              if (value == 'download') {
                _downloadVideo(context);
              } else if (value == 'share') {
                _shareVideo(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    const Icon(Icons.download_outlined, color: kWhite, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Download',
                      style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    const Icon(Icons.share_outlined, color: kWhite, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Share',
                      style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(child: _buildVideoBody()),
    );
  }

  Widget _buildVideoBody() {
    if (kIsWeb) {
      final bytes = _videoBytes;
      final mimeType = _mimeType;
      if (bytes == null || mimeType == null) {
        return const CircularProgressIndicator(color: kWhite);
      }
      return web_video.createVideoView(
        bytes,
        mimeType,
        _viewId,
      );
    }

    return FutureBuilder<void>(
      future: _nativeInit,
      builder: (context, snapshot) {
        final error = _error;
        if (error != null || snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error ?? 'Failed to play video: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
            ),
          );
        }

        final controller = _nativeController;
        if (controller == null || !controller.value.isInitialized) {
          return const CircularProgressIndicator(color: kWhite);
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            Positioned(
              bottom: 22,
              left: 18,
              right: 18,
              child: _NativeVideoControls(controller: controller),
            ),
          ],
        );
      },
    );
  }
}

class _NativeVideoControls extends StatefulWidget {
  final VideoPlayerController controller;

  const _NativeVideoControls({required this.controller});

  @override
  State<_NativeVideoControls> createState() => _NativeVideoControlsState();
}

class _NativeVideoControlsState extends State<_NativeVideoControls> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _NativeVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: kWhite,
            ),
            onPressed: () {
              value.isPlaying
                  ? widget.controller.pause()
                  : widget.controller.play();
            },
          ),
          Expanded(
            child: VideoProgressIndicator(
              widget.controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: kLimeGreen,
                bufferedColor: kMediumGrey,
                backgroundColor: kDarkGrey,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_format(value.position)} / ${_format(value.duration)}',
            style: GoogleFonts.inter(color: kWhite, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _LoadedVideo {
  final Uint8List bytes;
  final String mimeType;
  final String fileName;

  const _LoadedVideo({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });
}
