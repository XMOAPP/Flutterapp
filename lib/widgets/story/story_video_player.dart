import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../theme.dart';

class StoryVideoPlayer extends StatefulWidget {
  final Uint8List? videoBytes;
  final String? videoUrl;
  final String mimeType;
  final bool looping;
  final bool paused;
  final bool enableTapToPause;
  final ValueChanged<double>? onProgress;
  final VoidCallback? onCompleted;

  const StoryVideoPlayer.bytes({
    super.key,
    required Uint8List bytes,
    required this.mimeType,
    this.looping = true,
    this.paused = false,
    this.enableTapToPause = true,
    this.onProgress,
    this.onCompleted,
  })  : videoBytes = bytes,
        videoUrl = null;

  const StoryVideoPlayer.url({
    super.key,
    required String url,
    this.mimeType = 'video/mp4',
    this.looping = true,
    this.paused = false,
    this.enableTapToPause = true,
    this.onProgress,
    this.onCompleted,
  })  : videoBytes = null,
        videoUrl = url;

  @override
  State<StoryVideoPlayer> createState() => _StoryVideoPlayerState();
}

class _StoryVideoPlayerState extends State<StoryVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  File? _previewFile;
  String? _error;
  bool _completedNotified = false;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _initialize();
  }

  @override
  void didUpdateWidget(covariant StoryVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoBytes != widget.videoBytes ||
        oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.mimeType != widget.mimeType) {
      _initializeFuture = _reinitialize();
    } else if (oldWidget.paused != widget.paused) {
      _syncPlaybackState();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleVideoUpdate);
    _controller?.dispose();
    _deletePreviewFile();
    super.dispose();
  }

  Future<void> _reinitialize() async {
    final previousController = _controller;
    _controller = null;
    previousController?.removeListener(_handleVideoUpdate);
    await previousController?.dispose();
    await _deletePreviewFile();
    await _initialize();
  }

  Future<void> _initialize() async {
    _error = null;
    _completedNotified = false;

    try {
      final videoUrl = widget.videoUrl;
      final videoBytes = widget.videoBytes;

      if (videoUrl != null) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      } else if (videoBytes != null) {
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}/story_preview_${DateTime.now().microsecondsSinceEpoch}${_fileExtensionForMime(widget.mimeType)}',
        );
        await file.writeAsBytes(videoBytes, flush: true);
        _previewFile = file;
        _controller = VideoPlayerController.file(file);
      } else {
        _error = 'Video unavailable';
        return;
      }

      final controller = _controller!;
      await controller.initialize();
      await controller.setLooping(widget.looping);
      controller.addListener(_handleVideoUpdate);
      await _syncPlaybackState();
      setStateIfMounted(() {});
    } catch (e) {
      setStateIfMounted(() => _error = 'Unable to play video');
    }
  }

  Future<void> _syncPlaybackState() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (widget.paused) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  void _handleVideoUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration.inMilliseconds <= 0) return;

    final progress = position.inMilliseconds / duration.inMilliseconds;
    widget.onProgress?.call(progress.clamp(0.0, 1.0));

    final isComplete = !widget.looping &&
        position.inMilliseconds >= duration.inMilliseconds - 150;
    if (isComplete && !_completedNotified) {
      _completedNotified = true;
      widget.onCompleted?.call();
    } else if (!isComplete && _completedNotified) {
      _completedNotified = false;
    }
  }

  Future<void> _deletePreviewFile() async {
    final file = _previewFile;
    _previewFile = null;
    if (file == null) return;

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Temporary preview cleanup is best-effort.
    }
  }

  String _fileExtensionForMime(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'video/quicktime':
        return '.mov';
      case 'video/webm':
        return '.webm';
      case 'video/3gpp':
        return '.3gp';
      case 'video/x-m4v':
        return '.m4v';
      default:
        return '.mp4';
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setStateIfMounted(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kBlack,
      child: FutureBuilder<void>(
        future: _initializeFuture,
        builder: (context, snapshot) {
          final controller = _controller;
          if (_error != null) return _buildFallback(_error!);
          if (snapshot.connectionState != ConnectionState.done ||
              controller == null ||
              !controller.value.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(color: kLimeGreen),
            );
          }

          return GestureDetector(
            onTap: widget.enableTapToPause ? _togglePlayback : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
                if (!controller.value.isPlaying)
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: kWhite,
                      size: 42,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFallback(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_circle_outline, color: kLimeGreen, size: 64),
          const SizedBox(height: 12),
          Text(
            message,
            style: GoogleFonts.inter(color: kWhite, fontSize: 14),
          ),
        ],
      ),
    );
  }

  void setStateIfMounted(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }
}
