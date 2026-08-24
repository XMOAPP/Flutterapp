import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';
import 'camera_capture_screen.dart';

class MediaPreviewScreen extends StatefulWidget {
  final CameraCaptureMediaType type;
  final Uint8List bytes;
  final String? filePath;
  final String fileName;
  final String mimeType;

  const MediaPreviewScreen({
    super.key,
    required this.type,
    required this.bytes,
    this.filePath,
    required this.fileName,
    required this.mimeType,
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  final _captionController = TextEditingController();
  VideoPlayerController? _videoController;
  File? _tempVideoFile;
  bool _loadingVideo = false;
  String? _videoError;

  bool get _isVideo => widget.type == CameraCaptureMediaType.video;

  @override
  void initState() {
    super.initState();
    if (_isVideo) _prepareVideoPreview();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.removeListener(_refreshVideo);
    _videoController?.dispose();
    final temp = _tempVideoFile;
    if (temp != null && temp.existsSync()) {
      try {
        temp.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _prepareVideoPreview() async {
    setState(() {
      _loadingVideo = true;
      _videoError = null;
    });

    try {
      final sourcePath = widget.filePath;
      if (sourcePath != null && sourcePath.isNotEmpty) {
        final sourceFile = File(sourcePath);
        if (await sourceFile.exists()) {
          final controller = VideoPlayerController.file(
            sourceFile,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            viewType: _preferredVideoViewType,
          );
          await controller.initialize();
          controller
            ..setLooping(true)
            ..addListener(_refreshVideo);
          if (!mounted) {
            await controller.dispose();
            return;
          }
          setState(() {
            _videoController = controller;
            _loadingVideo = false;
          });
          return;
        }
      }
      final dir = Directory.systemTemp;
      final tempFile = File(
        '${dir.path}/xmo_preview_${DateTime.now().microsecondsSinceEpoch}_${widget.fileName}',
      );
      await tempFile.writeAsBytes(widget.bytes, flush: true);

      final controller = VideoPlayerController.file(
        tempFile,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        viewType: _preferredVideoViewType,
      );
      await controller.initialize();
      controller
        ..setLooping(true)
        ..addListener(_refreshVideo);

      if (!mounted) {
        await controller.dispose();
        await tempFile.delete();
        return;
      }

      setState(() {
        _tempVideoFile = tempFile;
        _videoController = controller;
        _loadingVideo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVideo = false;
        _videoError = 'Unable to preview video';
      });
    }
  }

  void _refreshVideo() {
    if (mounted) setState(() {});
  }

  void _send() {
    Navigator.pop(
      context,
      CameraCaptureResult(
        type: widget.type,
        bytes: widget.bytes,
        filePath: widget.filePath,
        fileName: widget.fileName,
        mimeType: widget.mimeType,
        caption: _captionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildPreview()),
            Positioned(
              top: 12,
              left: 12,
              child: _roundButton(
                icon: Icons.close,
                onTap: () => Navigator.pop(context),
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _buildCaptionBar()),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (!_isVideo) {
      return Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: kLightGrey,
              size: 48,
            ),
          ),
        ),
      );
    }

    final controller = _videoController;
    if (_loadingVideo) {
      return const Center(child: CircularProgressIndicator(color: kLimeGreen));
    }
    if (_videoError != null || controller == null) {
      return Center(
        child: Text(
          _videoError ?? 'Unable to preview video',
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
        ),
      );
    }

    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        Center(
          child: GestureDetector(
            onTap: () {
              controller.value.isPlaying
                  ? controller.pause()
                  : controller.play();
              setState(() {});
            },
            child: AnimatedOpacity(
              opacity: controller.value.isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 160),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: kDarkerGrey,
        border: Border(top: BorderSide(color: kDarkGrey, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: kDarkGrey,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _captionController,
                  style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Add a caption',
                    hintStyle: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: kLimeGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, color: kBlack, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: kWhite, size: 28),
      ),
    );
  }
}

VideoViewType get _preferredVideoViewType {
  return defaultTargetPlatform == TargetPlatform.android
      ? VideoViewType.platformView
      : VideoViewType.textureView;
}
