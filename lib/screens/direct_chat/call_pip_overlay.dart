import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../services/matrix_service.dart';
import '../../services/voip_service.dart';
import '../../theme.dart';
import '../../widgets/story/story_avatar.dart';

/// Floating picture-in-picture overlay shown while the user navigates the app
/// during an active call. Draggable, shows video or avatar, has mini controls.
class CallPipOverlay extends StatefulWidget {
  const CallPipOverlay({super.key});

  @override
  State<CallPipOverlay> createState() => _CallPipOverlayState();
}

class _CallPipOverlayState extends State<CallPipOverlay> {
  static const double _pipWidth = 150.0;
  static const double _pipHeight = 210.0;

  Offset _position = const Offset(20, 80);
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  StreamSubscription? _stateSub;
  bool _muted = false;

  VoipService get _voip => VoipService();

  @override
  void initState() {
    super.initState();
    _voip.pipMode.addListener(_onPipChanged);
    _voip.fullscreenCallRouteDepth.addListener(_onPipChanged);
    _startIfNeeded();
  }

  void _onPipChanged() {
    if (mounted) setState(() {});
    if (_voip.pipMode.value) {
      _startIfNeeded();
    } else {
      _stopTimers();
    }
  }

  void _startIfNeeded() {
    final session = _voip.activeSession;
    final groupCall = _voip.activeGroupCall;
    if (session == null && groupCall == null) return;
    if (groupCall != null && session == null) {
      _stateSub?.cancel();
      _stateSub = groupCall.onGroupCallState.stream.listen((state) {
        if (!mounted) return;
        if (state == GroupCallState.Ended) {
          _voip.pipMode.value = false;
        }
        setState(() {});
      });
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final connectedAt = _voip.groupCallConnectedAt;
        setState(() {
          _callDuration = connectedAt == null
              ? Duration.zero
              : DateTime.now().difference(connectedAt);
        });
      });
      return;
    }

    // Sync mute state from session
    _muted = session!.isMicrophoneMuted;

    // Subscribe to call state changes
    _stateSub?.cancel();
    _stateSub = session.onCallStateChanged.stream.listen((state) {
      if (!mounted) return;
      if (state == CallState.kEnded) {
        _voip.pipMode.value = false;
      }
      setState(() {});
    });

    // Start duration timer
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final connectedAt = _voip.callConnectedAt;
      if (connectedAt != null) {
        setState(() {
          _callDuration = DateTime.now().difference(connectedAt);
        });
      }
    });

    // Seed initial duration
    final connectedAt = _voip.callConnectedAt;
    if (connectedAt != null) {
      _callDuration = DateTime.now().difference(connectedAt);
    }
  }

  void _stopTimers() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _stateSub?.cancel();
    _stateSub = null;
  }

  @override
  void dispose() {
    _voip.pipMode.removeListener(_onPipChanged);
    _voip.fullscreenCallRouteDepth.removeListener(_onPipChanged);
    _stopTimers();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _toggleMic() async {
    final session = _voip.activeSession;
    if (session == null) return;
    await session.setMicrophoneMuted(!session.isMicrophoneMuted);
    if (mounted) setState(() => _muted = session.isMicrophoneMuted);
  }

  Future<void> _endCall() async {
    final session = _voip.activeSession;
    if (session == null) return;
    await session.hangup(CallErrorCode.UserHangup);
  }

  void _maximize() => _voip.maximizeCall();

  @override
  Widget build(BuildContext context) {
    if (!_voip.pipMode.value ||
        _voip.isFullscreenCallRouteVisible ||
        (_voip.activeSession == null && _voip.activeGroupCall == null)) {
      return const SizedBox.shrink();
    }

    final session = _voip.activeSession;
    final groupCall = _voip.activeGroupCall;
    final screenSize = MediaQuery.of(context).size;

    // Clamp position within screen bounds
    final clampedX = _position.dx.clamp(0.0, screenSize.width - _pipWidth);
    final clampedY =
        _position.dy.clamp(0.0, screenSize.height - _pipHeight - 40);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() => _position = Offset(
                _position.dx + d.delta.dx,
                _position.dy + d.delta.dy,
              ));
        },
        onTap: _maximize,
        child: Material(
          color: Colors.transparent,
          child: session != null
              ? _buildCard(session)
              : _buildGroupCard(groupCall!),
        ),
      ),
    );
  }

  Widget _buildGroupCard(GroupCall groupCall) {
    final isVideo = groupCall.type == GroupCallType.Video;
    final remoteStreams = groupCall.userMediaStreams.where(
      (stream) => !stream.isLocal(),
    );
    final stream = remoteStreams.isEmpty ? null : remoteStreams.first;
    final renderer = _rendererFor(stream);
    final title = MatrixService.cleanName(
      MatrixService().getResolvedDisplayName(groupCall.room),
    );

    return Container(
      width: _pipWidth,
      height: _pipHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: kLimeGreen.withValues(alpha: 0.08),
            blurRadius: 20,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: [
            Positioned.fill(
              child: isVideo && renderer != null
                  ? webrtc.RTCVideoView(
                      renderer,
                      objectFit: webrtc
                          .RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Center(
                      child: StoryAvatar(
                        userName: title,
                        avatarUrl: groupCall.room.avatar?.toString(),
                        size: 54,
                        fallbackIcon: Icons.group,
                      ),
                    ),
            ),
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formatDuration(_callDuration),
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _miniButton(
                      icon: groupCall.isMicrophoneMuted
                          ? Icons.mic_off
                          : Icons.mic,
                      color: groupCall.isMicrophoneMuted ? kLimeGreen : kWhite,
                      onTap: () async {
                        await groupCall.setMicrophoneMuted(
                          !groupCall.isMicrophoneMuted,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    _miniButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onTap: () => VoipService().canEndGroupCall(groupCall)
                          ? groupCall.terminate()
                          : groupCall.leave(),
                    ),
                    _miniButton(
                      icon: Icons.open_in_full,
                      color: kWhite,
                      onTap: _maximize,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(CallSession session) {
    final isVideo = session.type == CallType.kVideo;
    final remoteRenderer = _rendererFor(session.remoteUserMediaStream);
    final title = MatrixService.cleanName(
      MatrixService().getResolvedDisplayName(session.room),
    );

    return Container(
      width: _pipWidth,
      height: _pipHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: kLimeGreen.withValues(alpha: 0.08),
            blurRadius: 20,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: [
            // ── Video / Avatar background ─────────────────────────────────
            Positioned.fill(
              child: isVideo && remoteRenderer != null
                  ? webrtc.RTCVideoView(
                      remoteRenderer,
                      objectFit: webrtc
                          .RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF1A1A1A),
                            Color(0xFF0A0A0A),
                          ],
                        ),
                      ),
                      child: Center(
                        child: StoryAvatar(
                          userName: title,
                          avatarUrl: session.room.avatar?.toString(),
                          size: 52,
                        ),
                      ),
                    ),
            ),

            // ── Duration badge (top) ──────────────────────────────────────
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formatDuration(_callDuration),
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom controls ───────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _miniButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      color: _muted ? kLimeGreen : kWhite,
                      onTap: _toggleMic,
                    ),
                    _miniButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onTap: _endCall,
                    ),
                    _miniButton(
                      icon: Icons.open_in_full,
                      color: kWhite,
                      onTap: _maximize,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  webrtc.RTCVideoRenderer? _rendererFor(WrappedMediaStream? stream) {
    if (stream?.stream == null) return null;
    final renderer = stream?.renderer;
    return renderer is webrtc.RTCVideoRenderer ? renderer : null;
  }
}
