import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';

enum CameraCaptureMediaType { image, video }

class CameraCaptureResult {
  final CameraCaptureMediaType type;
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String caption;

  const CameraCaptureResult({
    this.type = CameraCaptureMediaType.image,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.caption = '',
  });
}

class CameraCaptureScreen extends StatefulWidget {
  final bool allowVideo;
  final bool showCaption;

  const CameraCaptureScreen({
    super.key,
    this.allowVideo = true,
    this.showCaption = true,
  });

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  final _captionController = TextEditingController();
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  VideoPlayerController? _videoPreviewController;
  Timer? _recordingTimer;
  int _cameraIndex = 0;
  bool _loading = true;
  bool _capturing = false;
  bool _videoMode = false;
  bool _recording = false;
  bool _flashOn = false;
  Uint8List? _capturedBytes;
  String? _capturedFileName;
  String? _capturedVideoPath;
  Duration _recordingDuration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _captionController.dispose();
    _videoPreviewController?.removeListener(_refreshVideoPreview);
    _videoPreviewController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _error = 'No camera found';
          _loading = false;
        });
        return;
      }

      final rearIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      _cameras = cameras;
      _cameraIndex = rearIndex >= 0 ? rearIndex : 0;
      await _initializeCamera(_cameras[_cameraIndex]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to open camera: $e';
        _loading = false;
      });
    }
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      await _applyFlashMode(controller);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _error = 'Failed to initialize camera: $e';
        _loading = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _capturing || _loading) return;
    setState(() => _loading = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera(_cameras[_cameraIndex]);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }

    final nextFlashState = !_flashOn;
    setState(() => _flashOn = nextFlashState);

    try {
      await controller.setFlashMode(
        nextFlashState ? FlashMode.torch : FlashMode.off,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _flashOn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Flash is not available on this camera'),
          backgroundColor: kDarkGrey,
        ),
      );
    }
  }

  Future<void> _applyFlashMode(CameraController controller) async {
    try {
      await controller.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      _flashOn = false;
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }

    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _capturedBytes = bytes;
        _capturedFileName =
            'camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
        _capturing = false;
        _flashOn = false;
      });
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Some devices do not support changing flash after capture.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleVideoRecording() async {
    if (!widget.allowVideo) return;
    if (_recording) {
      await _stopVideoRecording();
    } else {
      await _startVideoRecording();
    }
  }

  Future<void> _close() async {
    if (_recording) {
      try {
        await _controller?.stopVideoRecording();
      } catch (_) {
        // Best effort cleanup before closing.
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _startVideoRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing ||
        _recording) {
      return;
    }

    try {
      await controller.startVideoRecording();
      _recordingTimer?.cancel();
      setState(() {
        _recording = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopVideoRecording() async {
    final controller = _controller;
    if (controller == null || !_recording) return;

    setState(() => _capturing = true);
    _recordingTimer?.cancel();

    try {
      final video = await controller.stopVideoRecording();
      final previewController = VideoPlayerController.file(File(video.path));
      await previewController.initialize();
      await previewController.setLooping(true);
      previewController.addListener(_refreshVideoPreview);
      await previewController.play();
      if (!mounted) {
        await previewController.dispose();
        return;
      }

      _videoPreviewController?.removeListener(_refreshVideoPreview);
      await _videoPreviewController?.dispose();
      setState(() {
        _videoPreviewController = previewController;
        _capturedVideoPath = video.path;
        _capturedFileName =
            'camera_${DateTime.now().millisecondsSinceEpoch}.mp4';
        _capturing = false;
        _recording = false;
        _flashOn = false;
      });
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Some devices do not support changing flash after recording.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _recording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to record video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _refreshVideoPreview() {
    if (mounted) setState(() {});
  }

  void _retake() {
    _videoPreviewController?.removeListener(_refreshVideoPreview);
    setState(() {
      _capturedBytes = null;
      _capturedFileName = null;
      _capturedVideoPath = null;
      _videoPreviewController?.pause();
      _videoPreviewController?.dispose();
      _videoPreviewController = null;
      _captionController.clear();
    });
  }

  void _sendCapturedPhoto() {
    final bytes = _capturedBytes;
    final fileName = _capturedFileName;
    if (bytes == null || bytes.isEmpty || fileName == null) return;

    Navigator.pop(
      context,
      CameraCaptureResult(
        bytes: bytes,
        fileName: fileName,
        mimeType: 'image/jpeg',
        caption: widget.showCaption ? _captionController.text.trim() : '',
      ),
    );
  }

  Future<void> _sendCapturedVideo() async {
    final path = _capturedVideoPath;
    final fileName = _capturedFileName;
    if (path == null || fileName == null) return;

    final bytes = await File(path).readAsBytes();
    if (!mounted || bytes.isEmpty) return;

    Navigator.pop(
      context,
      CameraCaptureResult(
        type: CameraCaptureMediaType.video,
        bytes: bytes,
        fileName: fileName,
        mimeType: 'video/mp4',
        caption: widget.showCaption ? _captionController.text.trim() : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final capturedBytes = _capturedBytes;
    final videoController = _videoPreviewController;

    if (capturedBytes != null) {
      return _buildCapturedPreview(capturedBytes);
    }
    if (_capturedVideoPath != null && videoController != null) {
      return _buildCapturedVideoPreview(videoController);
    }

    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildPreview(controller),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _roundButton(
                icon: Icons.close,
                onTap: () => _close(),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _roundButton(
                icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                onTap: _loading || _capturing ? null : _toggleFlash,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 54, height: 54),
                    GestureDetector(
                      onTap: _capturing
                          ? null
                          : _videoMode
                              ? _toggleVideoRecording
                              : _capture,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: _capturing || _recording ? 42 : 58,
                            height: _capturing || _recording ? 42 : 58,
                            decoration: BoxDecoration(
                              color: _recording ? Colors.red : Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: _capturing && !_recording
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.black,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    _roundButton(
                      icon: Icons.cameraswitch_outlined,
                      onTap: _cameras.length > 1 && !_loading && !_capturing
                          ? _switchCamera
                          : null,
                      size: 58,
                      iconSize: 30,
                      backgroundOpacity: 0.22,
                    ),
                  ],
                ),
              ),
            ),
            if (widget.allowVideo)
              Positioned(
                left: 0,
                right: 0,
                bottom: 120,
                child: Center(
                  child: _buildModeSwitch(),
                ),
              ),
            if (_recording)
              Positioned(
                top: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: _buildRecordingPill(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapturedPreview(Uint8List bytes) {
    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _roundButton(
                icon: Icons.close,
                onTap: _retake,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildSendBar(onSend: _sendCapturedPhoto),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapturedVideoPreview(VideoPlayerController controller) {
    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _roundButton(
                icon: Icons.close,
                onTap: _retake,
              ),
            ),
            Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    controller.value.isPlaying
                        ? controller.pause()
                        : controller.play();
                  });
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildSendBar(onSend: () => _sendCapturedVideo()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendBar({required VoidCallback onSend}) {
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
            if (widget.showCaption)
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
              )
            else
              const Spacer(),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: kLimeGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: kBlack,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton('Photo', !_videoMode, () {
            if (_recording || _capturing) return;
            setState(() => _videoMode = false);
          }),
          _modeButton('Video', _videoMode, () {
            if (_recording || _capturing) return;
            setState(() => _videoMode = true);
          }),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.black.withValues(alpha: 0.62)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingPill() {
    final minutes =
        _recordingDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        _recordingDuration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$minutes:$seconds',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(CameraController? controller) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kLimeGreen),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return Center(
      child: CameraPreview(controller),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required VoidCallback? onTap,
    double size = 48,
    double? iconSize,
    double backgroundOpacity = 0.45,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: backgroundOpacity),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: onTap == null ? Colors.white38 : Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}
