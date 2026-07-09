import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';
import '../../theme.dart';
import '../../screens/web_download_stub.dart'
    if (dart.library.js_interop) '../../screens/web_download.dart'
    as web_download;
import '../../screens/web_video_view_stub.dart'
    if (dart.library.js_interop) '../../screens/web_video_view.dart'
    as web_video;
import '../../screens/native_share_stub.dart'
    if (dart.library.io) '../../screens/native_share.dart' as native_share;
import 'native_video_controller_stub.dart'
    if (dart.library.io) 'native_video_controller_io.dart';

/// Fullscreen in-app video player with download functionality
class FullscreenVideoPlayer extends StatefulWidget {
  final Uint8List? videoBytes;
  final String? mimeType;
  final String title;
  final Future<MatrixFile>? videoFuture;
  final Future<MatrixFile> Function()? downloadFuture;
  final Uri? videoUrl;
  final Map<String, String> videoHeaders;
  final String loadingLabel;
  final Future<void> Function()? onReply;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onDispose;

  const FullscreenVideoPlayer({
    super.key,
    required this.videoBytes,
    required this.mimeType,
    required this.title,
    this.loadingLabel = 'Opening...',
    this.downloadFuture,
    this.onReply,
    this.onDelete,
    this.onDispose,
  })  : videoFuture = null,
        videoUrl = null,
        videoHeaders = const <String, String>{};

  const FullscreenVideoPlayer.loading({
    super.key,
    required this.videoFuture,
    required this.title,
    this.loadingLabel = 'Opening...',
    this.downloadFuture,
    this.onReply,
    this.onDelete,
    this.onDispose,
  })  : videoBytes = null,
        mimeType = null,
        videoUrl = null,
        videoHeaders = const <String, String>{};

  const FullscreenVideoPlayer.network({
    super.key,
    required this.videoUrl,
    required this.videoHeaders,
    required this.title,
    this.loadingLabel = 'Loading video...',
    this.mimeType,
    this.downloadFuture,
    this.onReply,
    this.onDelete,
    this.onDispose,
  })  : videoBytes = null,
        videoFuture = null;

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
  bool _landscape = false;
  bool _showCenterControl = true;
  Timer? _centerControlTimer;

  @override
  void initState() {
    super.initState();
    _viewId = 'video_player_${DateTime.now().millisecondsSinceEpoch}';
    _videoBytes = widget.videoBytes;
    _mimeType = widget.mimeType;
    final future = widget.videoFuture;
    if (widget.videoUrl != null) {
      _nativeInit = _initNetworkVideo();
    } else if (future != null) {
      _nativeInit = _loadAndInitVideo(future);
    } else {
      _nativeInit = _initLoadedVideo();
    }
  }

  @override
  void dispose() {
    _centerControlTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (kIsWeb) {
      web_video.disposeVideoView(_viewId);
    }
    final onDispose = widget.onDispose;
    if (onDispose != null) {
      unawaited(onDispose());
    }
    _nativeController?.dispose();
    super.dispose();
  }

  Future<void> _initNativeVideo() async {
    final bytes = _videoBytes;
    final mimeType = _resolvedMimeType();
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

  Future<void> _initNetworkVideo() async {
    final url = widget.videoUrl;
    if (url == null) return;
    if (kIsWeb) {
      if (widget.videoHeaders.isNotEmpty) {
        throw UnsupportedError(
          'Authenticated browser video streaming is not supported.',
        );
      }
      web_video.registerVideoUrlView(_viewId, url.toString());
      return;
    }

    late final VideoPlayerController controller;
    try {
      controller = await createNativeNetworkVideoController(
        url: url,
        headers: widget.videoHeaders,
      );
    } catch (_) {
      final fallback = widget.downloadFuture;
      if (fallback == null) rethrow;
      await _loadAndInitVideo(fallback());
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _nativeController = controller);
  }

  Future<void> _loadAndInitVideo(Future<MatrixFile> future) async {
    try {
      final matrixFile = await future;
      if (!mounted) return;
      _videoBytes = matrixFile.bytes;
      _mimeType = _effectiveVideoMimeType(
        matrixFile.mimeType,
        matrixFile.name,
        matrixFile.bytes,
      );
      await _initLoadedVideo();
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load video: $e');
    }
  }

  Future<void> _initLoadedVideo() async {
    final bytes = _videoBytes;
    final mimeType = _resolvedMimeType();
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
          content: Text(kIsWeb
              ? 'Downloaded: ${video.fileName}'
              : 'Downloaded successfully'),
          backgroundColor: kLimeGreen,
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

  void _closeAndRun(Future<void> Function() action) {
    Navigator.maybePop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      action();
    });
  }

  Future<void> _rotateVideo() async {
    final nextLandscape = !_landscape;
    await SystemChrome.setPreferredOrientations(
      nextLandscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    if (mounted) {
      setState(() => _landscape = nextLandscape);
    }
  }

  void _scheduleCenterControlHide() {
    _centerControlTimer?.cancel();
    _centerControlTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _showCenterControl = false);
      }
    });
  }

  void _showCenterControlTemporarily() {
    setState(() => _showCenterControl = true);
    _scheduleCenterControlHide();
  }

  Future<_LoadedVideo?> _readyVideo(BuildContext context) async {
    final downloadFuture = widget.downloadFuture;
    if (_videoBytes == null && downloadFuture != null) {
      try {
        final matrixFile = await downloadFuture();
        _videoBytes = matrixFile.bytes;
        _mimeType = _effectiveVideoMimeType(
          matrixFile.mimeType,
          matrixFile.name,
          matrixFile.bytes,
        );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Video is still loading: $e'),
              backgroundColor: kDarkerGrey,
            ),
          );
        }
        return null;
      }
    }

    if (_videoBytes == null || _resolvedMimeType() == null) {
      try {
        await _nativeInit;
      } catch (_) {
        // The error is already displayed by the player body.
      }
    }

    final bytes = _videoBytes;
    final mimeType = _resolvedMimeType();
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

  String? _resolvedMimeType() {
    final bytes = _videoBytes;
    return _effectiveVideoMimeType(_mimeType, widget.title, bytes);
  }

  String? _effectiveVideoMimeType(
    String? mimeType,
    String fileName,
    Uint8List? bytes,
  ) {
    final normalized = mimeType?.trim().toLowerCase();
    if (normalized != null &&
        normalized.isNotEmpty &&
        normalized != 'application/octet-stream') {
      return normalized;
    }
    return lookupMimeType(fileName, headerBytes: bytes) ?? normalized;
  }

  String _videoFileName(String mimeType) {
    final title =
        widget.title.trim().isEmpty ? 'xmo_video' : widget.title.trim();
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
      backgroundColor: kBlack,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: _buildVideoBody()),
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: kWhite, size: 28),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: kWhite, size: 28),
                color: const Color(0xFF262728),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (value) {
                  if (value == 'download') {
                    _downloadVideo(context);
                  } else if (value == 'share') {
                    _shareVideo(context);
                  } else if (value == 'reply') {
                    final action = widget.onReply;
                    if (action != null) _closeAndRun(action);
                  } else if (value == 'delete') {
                    final action = widget.onDelete;
                    if (action != null) _closeAndRun(action);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        const Icon(Icons.download, color: kWhite, size: 20),
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
                        const Icon(Icons.share, color: kWhite, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'Share',
                          style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onReply != null)
                    PopupMenuItem(
                      value: 'reply',
                      child: Row(
                        children: [
                          const Icon(Icons.reply, color: kWhite, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Reply',
                            style:
                                GoogleFonts.inter(color: kWhite, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  if (widget.onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Delete Message',
                            style: GoogleFonts.inter(
                                color: Colors.red, fontSize: 14),
                          ),
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

  Widget _buildVideoBody() {
    if (kIsWeb) {
      final url = widget.videoUrl;
      if (url != null && widget.videoHeaders.isEmpty) {
        return FutureBuilder<void>(
          future: _nativeInit,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to play video: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
                ),
              );
            }
            return web_video.createVideoView(
              Uint8List(0),
              widget.mimeType ?? 'video/mp4',
              _viewId,
            );
          },
        );
      }

      final bytes = _videoBytes;
      final mimeType = _resolvedMimeType();
      if (bytes == null || mimeType == null) {
        return _buildLoading();
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error ?? 'Failed to play video: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF262728),
                    foregroundColor: kWhite,
                  ),
                  onPressed: _openExternally,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(
                    'Open with',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          );
        }

        final controller = _nativeController;
        if (controller == null || !controller.value.isInitialized) {
          return _buildLoading();
        }

        if (_showCenterControl && controller.value.isPlaying) {
          _scheduleCenterControlHide();
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _showCenterControlTemporarily,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
              Center(
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    if (!_showCenterControl) return const SizedBox.shrink();

                    return GestureDetector(
                      onTap: () async {
                        value.isPlaying
                            ? await controller.pause()
                            : await controller.play();
                        _showCenterControlTemporarily();
                      },
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: kWhite,
                          size: 52,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _NativeVideoControls(
                  controller: controller,
                  onRotate: _rotateVideo,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: kWhite),
        const SizedBox(height: 14),
        Text(
          widget.loadingLabel,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _openExternally() async {
    final video = await _readyVideo(context);
    if (video == null) return;
    try {
      await native_share.openFile(
        video.bytes,
        video.fileName,
        mimeType: video.mimeType,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _NativeVideoControls extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onRotate;

  const _NativeVideoControls({
    required this.controller,
    required this.onRotate,
  });

  @override
  State<_NativeVideoControls> createState() => _NativeVideoControlsState();
}

class _NativeVideoControlsState extends State<_NativeVideoControls> {
  bool _muted = false;

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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '${_format(value.position)} / ${_format(value.duration)}',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: kWhite,
                  size: 22,
                ),
                onPressed: _toggleMute,
              ),
              IconButton(
                icon: const Icon(Icons.screen_rotation_rounded,
                    color: kWhite, size: 24),
                onPressed: widget.onRotate,
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: kAudioBlue,
              inactiveTrackColor: kWhite.withValues(alpha: 0.24),
              thumbColor: kWhite,
              overlayColor: kAudioBlue.withValues(alpha: 0.18),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: _progressValue(value),
              min: 0,
              max: 1,
              onChanged: _seekToFraction,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMute() async {
    final nextMuted = !_muted;
    await widget.controller.setVolume(nextMuted ? 0 : 1);
    if (mounted) {
      setState(() => _muted = nextMuted);
    }
  }

  double _progressValue(VideoPlayerValue value) {
    final durationMs = value.duration.inMilliseconds;
    if (durationMs <= 0) return 0;
    return (value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
  }

  Future<void> _seekToFraction(double fraction) async {
    final duration = widget.controller.value.duration;
    if (duration.inMilliseconds <= 0) return;
    final position = Duration(
      milliseconds: (duration.inMilliseconds * fraction).round(),
    );
    await widget.controller.seekTo(position);
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
