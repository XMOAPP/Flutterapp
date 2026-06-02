import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../services/matrix_service.dart';
import '../../services/voip_service.dart';
import '../../theme.dart';
import '../../widgets/story/story_avatar.dart';

class DirectCallScreen extends StatefulWidget {
  final CallSession session;

  const DirectCallScreen({
    super.key,
    required this.session,
  });

  @override
  State<DirectCallScreen> createState() => _DirectCallScreenState();
}

class _DirectCallScreenState extends State<DirectCallScreen> {
  final List<StreamSubscription> _subscriptions = [];
  bool _ending = false;
  bool _closingWithoutPip = false;
  bool _speakerOn = false;

  // ── Call duration timer ────────────────────────────────────────────────────
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;

  // ── Draggable local video position ─────────────────────────────────────────
  Offset _localVideoOffset = const Offset(16, 18);

  CallSession get _session => widget.session;
  bool get _isVideoCall => _session.type == CallType.kVideo;
  bool get _isIncoming => _session.direction == CallDirection.kIncoming;
  bool get _canAnswer => _isIncoming && _session.state == CallState.kRinging;
  bool get _shouldKeepCallInPip =>
      !_closingWithoutPip && !_ending && _session.state != CallState.kEnded;

  @override
  void initState() {
    super.initState();
    VoipService().enterFullscreenCallRoute();
    _subscriptions.add(
      _session.onCallStateChanged.stream.listen((_) => _handleCallUpdate()),
    );
    _subscriptions.add(
      _session.onCallStreamsChanged.stream.listen((_) => _handleCallUpdate()),
    );
    _subscriptions.add(
      _session.onStreamAdd.stream.listen((_) => _handleCallUpdate()),
    );
    _subscriptions.add(
      _session.onStreamRemoved.stream.listen((_) => _handleCallUpdate()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isVideoCall) _enableSpeaker();
      _startDurationTimerIfConnected();
    });
  }

  void _handleCallUpdate() {
    if (!mounted) return;
    setState(() {});

    if (_session.state == CallState.kConnected && _isVideoCall) {
      _enableSpeaker();
    }
    _startDurationTimerIfConnected();

    if (_session.state == CallState.kEnded && !_ending) {
      _ending = true;
      _closingWithoutPip = true;
      _durationTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    VoipService().exitFullscreenCallRoute();
    if (_shouldKeepCallInPip) {
      VoipService().minimizeCall();
      VoipService().ensurePipVisibleAfterCallRouteClosed();
    }
    super.dispose();
  }

  Future<void> _answer() async {
    try {
      await _session.answer();
    } catch (e) {
      _showError('Failed to answer call: $e');
    }
  }

  Future<void> _reject() async {
    try {
      await _session.reject();
      _closingWithoutPip = true;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Failed to reject call: $e');
    }
  }

  Future<void> _hangup() async {
    try {
      await _session.hangup(CallErrorCode.UserHangup);
      _closingWithoutPip = true;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Failed to end call: $e');
    }
  }

  Future<void> _toggleMic() async {
    await _session.setMicrophoneMuted(!_session.isMicrophoneMuted);
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    await _session.setLocalVideoMuted(!_session.isLocalVideoMuted);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    if (_isVideoCall) return;
    try {
      _speakerOn = !_speakerOn;
      await webrtc.Helper.setSpeakerphoneOn(_speakerOn);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[DirectCallScreen] Speaker toggle failed: $e');
    }
  }

  Future<void> _enableSpeaker() async {
    try {
      await webrtc.Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint('[DirectCallScreen] Speaker enable failed: $e');
    }
  }

  Future<void> _flipCamera() async {
    try {
      final localStream = _session.localUserMediaStream;
      if (localStream?.stream != null) {
        final videoTracks = localStream!.stream!.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          await webrtc.Helper.switchCamera(videoTracks.first);
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      debugPrint('[DirectCallScreen] Camera flip failed: $e');
    }
  }

  void _minimizeToPopup() {
    if (!_shouldKeepCallInPip) return;
    VoipService().minimizeCall();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
  }

  void _handleRoutePop() {
    if (_shouldKeepCallInPip) {
      VoipService().minimizeCall();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  void _startDurationTimerIfConnected() {
    if (_session.state != CallState.kConnected || _durationTimer != null) {
      return;
    }

    void syncDuration() {
      final connectedAt = VoipService().callConnectedAt;
      if (connectedAt == null) return;
      final nextDuration = DateTime.now().difference(connectedAt);
      if (!mounted) {
        _callDuration = nextDuration;
        return;
      }
      setState(() => _callDuration = nextDuration);
    }

    syncDuration();
    _durationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => syncDuration(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = MatrixService.cleanName(
      MatrixService().getResolvedDisplayName(_session.room),
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _handleRoutePop();
      },
      child: Scaffold(
        backgroundColor: kBlack,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _buildCallBody(title)),
              // ── Top controls ───────────────────────────────────────────────
              if (!_canAnswer)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _topBarButton(
                    icon: Icons.picture_in_picture_alt,
                    onTap: _minimizeToPopup,
                  ),
                ),
              // ── Controls ───────────────────────────────────────────────────
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _buildControls(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBarButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 40,
    double iconSize = 20,
    Color? backgroundColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor ?? Colors.black.withValues(alpha: 0.55),
        ),
        child: Icon(icon, color: kWhite, size: iconSize),
      ),
    );
  }

  Widget _buildCallBody(String title) {
    final remoteRenderer = _rendererFor(_session.remoteUserMediaStream);
    final localRenderer = _rendererFor(_session.localUserMediaStream);

    return Column(
      children: [
        const SizedBox(height: 18),
        Text(
          title,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        _session.state == CallState.kConnected
            ? Text(
                _formatDuration(_callDuration),
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              )
            : Text(
                _stateLabel(),
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
              ),
        const SizedBox(height: 20),
        Expanded(
          child: _isVideoCall
              ? _buildVideoArea(remoteRenderer, localRenderer)
              : _buildVoiceArea(title, _session.room.avatar?.toString()),
        ),
      ],
    );
  }

  Widget _buildVideoArea(
    webrtc.RTCVideoRenderer? remoteRenderer,
    webrtc.RTCVideoRenderer? localRenderer,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Clamp local video within bounds
        const localW = 110.0;
        const localH = 155.0;
        final clampedX =
            _localVideoOffset.dx.clamp(0.0, constraints.maxWidth - localW);
        final clampedY =
            _localVideoOffset.dy.clamp(0.0, constraints.maxHeight - localH);

        return Stack(
          children: [
            // ── Remote video (full area) ──────────────────────────────────
            Positioned.fill(
              child: remoteRenderer != null
                  ? webrtc.RTCVideoView(
                      remoteRenderer,
                      objectFit: webrtc
                          .RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : _buildVoiceArea(
                      MatrixService().getResolvedDisplayName(_session.room),
                      _session.room.avatar?.toString(),
                    ),
            ),

            // ── Draggable local video ─────────────────────────────────────
            if (localRenderer != null && !_session.isLocalVideoMuted)
              Positioned(
                left: clampedX,
                top: clampedY,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _localVideoOffset = Offset(
                        _localVideoOffset.dx + details.delta.dx,
                        _localVideoOffset.dy + details.delta.dy,
                      );
                    });
                  },
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: localW,
                          height: localH,
                          decoration: BoxDecoration(
                            color: kDarkerGrey,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: webrtc.RTCVideoView(
                              localRenderer,
                              mirror: true,
                              objectFit: webrtc.RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildVoiceArea(String title, String? avatarUrl) {
    return Center(
      child: StoryAvatar(
        userName: title,
        avatarUrl: avatarUrl,
        size: 132,
      ),
    );
  }

  Widget _buildControls() {
    // ── Incoming ringing: swipe to answer + decline ──────────────────────────
    if (_canAnswer) {
      return Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _SwipeCallActionButton(
            icon: Icons.call_end,
            label: 'Decline',
            gradientColors: const [
              Color(0xFFFF6961),
              Color(0xFFFF3B30),
              Color(0xFFC21D1D),
            ],
            iconColor: kWhite,
            onCompleted: _reject,
          ),
          _SwipeCallActionButton(
            icon: _isVideoCall ? Icons.videocam : Icons.call,
            label: 'Answer',
            gradientColors: const [
              Color(0xFF34D875),
              Color(0xFF22C55E),
              Color(0xFF15803D),
            ],
            iconColor: kWhite,
            onCompleted: _answer,
          ),
        ],
      );
    }

    // ── Active call controls ────────────────────────────────────────────────
    final inactiveControlColor = _isVideoCall
        ? kBlack.withValues(alpha: 0.55)
        : kWhite.withValues(alpha: 0.10);
    final activeControlColor = kWhite.withValues(alpha: 0.18);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: _session.isMicrophoneMuted ? Icons.mic_off : Icons.mic,
          label: _session.isMicrophoneMuted ? 'Muted' : 'Mute',
          color: inactiveControlColor,
          iconColor: kWhite,
          onTap: _toggleMic,
        ),
        if (_isVideoCall)
          _CallButton(
            icon: Icons.cameraswitch,
            label: 'Rotate',
            color: inactiveControlColor,
            onTap: _flipCamera,
          )
        else
          _CallButton(
            icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
            label: 'Speaker',
            color: _speakerOn ? activeControlColor : inactiveControlColor,
            iconColor: kWhite,
            onTap: _toggleSpeaker,
          ),
        if (_isVideoCall)
          _CallButton(
            icon: _session.isLocalVideoMuted
                ? Icons.videocam_off
                : Icons.videocam,
            label: _session.isLocalVideoMuted ? 'Camera off' : 'Camera',
            color: inactiveControlColor,
            iconColor: kWhite,
            onTap: _toggleCamera,
          ),
        _CallButton(
          icon: Icons.call_end,
          label: 'End',
          color: Colors.red,
          onTap: _hangup,
        ),
      ],
    );
  }

  String _stateLabel() {
    switch (_session.state) {
      case CallState.kFledgling:
      case CallState.kInviteSent:
      case CallState.kWaitLocalMedia:
      case CallState.kCreateOffer:
        return _isIncoming ? 'Incoming call' : 'Calling...';
      case CallState.kRinging:
        return 'Incoming ${_isVideoCall ? 'video' : 'voice'} call';
      case CallState.kCreateAnswer:
      case CallState.kConnecting:
        return 'Connecting...';
      case CallState.kConnected:
        return 'Connected';
      case CallState.kEnded:
        return 'Call ended';
    }
  }

  webrtc.RTCVideoRenderer? _rendererFor(WrappedMediaStream? stream) {
    if (stream?.stream == null) return null;
    final renderer = stream?.renderer;
    return renderer is webrtc.RTCVideoRenderer ? renderer : null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SWIPE TO ANSWER SLIDER
// ═══════════════════════════════════════════════════════════════════════════════

class _SwipeCallActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<Color> gradientColors;
  final Color iconColor;
  final Future<void> Function() onCompleted;

  const _SwipeCallActionButton({
    required this.icon,
    required this.label,
    required this.gradientColors,
    required this.iconColor,
    required this.onCompleted,
  });

  @override
  State<_SwipeCallActionButton> createState() => _SwipeCallActionButtonState();
}

class _SwipeCallActionButtonState extends State<_SwipeCallActionButton>
    with SingleTickerProviderStateMixin {
  static const double _buttonSize = 68.0;
  static const double _maxLift = 34.0;
  static const double _completeThreshold = 0.62;

  double _dragProgress = 0.0;
  bool _completed = false;

  late final AnimationController _hintController;
  late final Animation<double> _hintAnimation;

  @override
  void initState() {
    super.initState();
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _hintAnimation = CurvedAnimation(
      parent: _hintController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _hintController.dispose();
    super.dispose();
  }

  void _finish() {
    if (_completed) return;
    setState(() {
      _completed = true;
      _dragProgress = 1.0;
    });
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final lift = _dragProgress * _maxLift;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (_completed) return;
        setState(() {
          _dragProgress =
              (_dragProgress - details.delta.dy / _maxLift).clamp(0.0, 1.0);
        });
      },
      onVerticalDragEnd: (_) {
        if (_completed) return;
        if (_dragProgress >= _completeThreshold) {
          _finish();
        } else {
          setState(() => _dragProgress = 0.0);
        }
      },
      child: SizedBox(
        width: 116,
        height: 134,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: 28,
              child: AnimatedBuilder(
                animation: _hintAnimation,
                builder: (context, _) {
                  final opacity = _dragProgress > 0.05
                      ? 0.0
                      : sin(_hintAnimation.value * pi);
                  return Opacity(
                    opacity: (opacity * 0.5).clamp(0.0, 0.5),
                    child: const Icon(
                      Icons.keyboard_arrow_up,
                      color: kWhite,
                      size: 26,
                    ),
                  );
                },
              ),
            ),
            Transform.translate(
              offset: Offset(0, -lift),
              child: AnimatedContainer(
                duration: _completed
                    ? const Duration(milliseconds: 220)
                    : Duration.zero,
                width: _buttonSize,
                height: _buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.gradientColors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.gradientColors[1].withValues(alpha: 0.38),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  _completed ? Icons.check : widget.icon,
                  color: widget.iconColor,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.label,
              style: GoogleFonts.inter(
                color: widget.label == 'Decline'
                    ? const Color(0xFFFF5B55)
                    : kWhite,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _SwipeToAnswerSlider extends StatefulWidget {
  final bool isVideoCall;
  final Future<void> Function() onAnswered;

  const _SwipeToAnswerSlider({
    required this.isVideoCall,
    required this.onAnswered,
  });

  @override
  State<_SwipeToAnswerSlider> createState() => _SwipeToAnswerSliderState();
}

class _SwipeToAnswerSliderState extends State<_SwipeToAnswerSlider>
    with SingleTickerProviderStateMixin {
  static const double _thumbSize = 62.0;
  static const double _trackPadding = 6.0;
  static const double _completeThreshold = 0.82;

  double _dragProgress = 0.0;
  bool _answered = false;

  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _shimmerAnimation = CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final innerWidth = trackWidth - _trackPadding * 2;
        final maxDrag = innerWidth - _thumbSize;
        final thumbOffset = _dragProgress * maxDrag;

        return Container(
          height: _thumbSize + _trackPadding * 2,
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular((_thumbSize + _trackPadding * 2) / 2),
            gradient: const LinearGradient(
              colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              // ── Animated hint arrows ────────────────────────────────────
              if (!_answered)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _shimmerAnimation,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _ArrowHintPainter(
                          progress: _shimmerAnimation.value,
                          dragProgress: _dragProgress,
                        ),
                      );
                    },
                  ),
                ),

              // ── Hint text ──────────────────────────────────────────────
              if (!_answered)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: _thumbSize + 8),
                    child: AnimatedOpacity(
                      opacity: _dragProgress < 0.3 ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        'Swipe to answer',
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Green trail ────────────────────────────────────────────
              Positioned(
                left: _trackPadding,
                top: _trackPadding,
                child: AnimatedContainer(
                  duration: _answered
                      ? const Duration(milliseconds: 250)
                      : Duration.zero,
                  width: thumbOffset + _thumbSize,
                  height: _thumbSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_thumbSize / 2),
                    gradient: LinearGradient(colors: [
                      const Color(0xFF22C55E).withValues(alpha: 0.20),
                      const Color(0xFF22C55E).withValues(alpha: 0.05),
                    ]),
                  ),
                ),
              ),

              // ── Draggable thumb ────────────────────────────────────────
              Positioned(
                left: _trackPadding + thumbOffset,
                top: _trackPadding,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_answered) return;
                    setState(() {
                      _dragProgress =
                          (_dragProgress + details.delta.dx / maxDrag)
                              .clamp(0.0, 1.0);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_answered) return;
                    if (_dragProgress >= _completeThreshold) {
                      setState(() {
                        _answered = true;
                        _dragProgress = 1.0;
                      });
                      widget.onAnswered();
                    } else {
                      setState(() => _dragProgress = 0.0);
                    }
                  },
                  child: AnimatedContainer(
                    duration: _answered
                        ? const Duration(milliseconds: 250)
                        : Duration.zero,
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF34D875),
                          Color(0xFF22C55E),
                          Color(0xFF15803D),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22C55E)
                              .withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      _answered
                          ? Icons.check
                          : (widget.isVideoCall ? Icons.videocam : Icons.call),
                      color: kBlack,
                      size: 26,
                    ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// ANIMATED ARROW HINTS
// ═══════════════════════════════════════════════════════════════════════════════

// ignore: unused_element
class _ArrowHintPainter extends CustomPainter {
  final double progress;
  final double dragProgress;

  _ArrowHintPainter({required this.progress, required this.dragProgress});

  @override
  void paint(Canvas canvas, Size size) {
    if (dragProgress > 0.15) return;

    const int arrowCount = 3;
    final double centerY = size.height / 2;
    final double startX = size.width * 0.45;
    const double spacing = 12.0;

    for (int i = 0; i < arrowCount; i++) {
      final double phase = (progress + i * 0.25) % 1.0;
      final double alpha = sin(phase * pi) * 0.35;
      if (alpha <= 0) continue;

      final paint = Paint()
        ..color = const Color(0xFF22C55E).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final x = startX + i * spacing;
      final path = Path()
        ..moveTo(x, centerY - 6)
        ..lineTo(x + 5, centerY)
        ..lineTo(x, centerY + 6);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowHintPainter old) =>
      old.progress != progress || old.dragProgress != dragProgress;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CALL BUTTON
// ═══════════════════════════════════════════════════════════════════════════════

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? iconColor;
  final Future<void> Function() onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDestructive = color == Colors.red;
    final isPrimary = color == kLimeGreen;
    final effectiveIconColor = iconColor ?? (isPrimary ? kBlack : kWhite);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDestructive ? null : color,
            gradient: isDestructive
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFF6961),
                      Color(0xFFFF3B30),
                      Color(0xFFC21D1D),
                    ],
                  )
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: Icon(icon, color: effectiveIconColor, size: 26),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            color: isDestructive ? Colors.red : kWhite,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
