import 'package:xmo/utils/user_facing_error.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../services/matrix_service.dart';
import '../../services/voip_service.dart';
import '../../theme.dart';
import '../../widgets/story/story_avatar.dart';
import 'group_call_screen.dart';

class IncomingGroupCallScreen extends StatefulWidget {
  final XmoGroupCall groupCall;

  const IncomingGroupCallScreen({super.key, required this.groupCall});

  @override
  State<IncomingGroupCallScreen> createState() =>
      _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState extends State<IncomingGroupCallScreen> {
  StreamSubscription? _stateSub;
  bool _busy = false;
  bool _closing = false;

  XmoGroupCall get _call => widget.groupCall;
  bool get _isVideoCall => _call.type == XmoGroupCallType.video;

  @override
  void initState() {
    super.initState();
    VoipService().enterFullscreenCallRoute();
    _stateSub = _call.stateStream.listen((state) {
      if (state == GroupCallState.ended && mounted && !_closing) {
        _closing = true;
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    VoipService().exitFullscreenCallRoute();
    super.dispose();
  }

  Future<void> _answer() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await VoipService().answerIncomingGroupCall(_call, openCallScreen: false);
      if (!mounted) return;
      _closing = true;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(groupCall: _call),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      _showError(safeUserFacingText('Unable to join call: $e'));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      VoipService().rejectGroupCall(_call);
      _closing = true;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError(safeUserFacingText('Unable to decline call: $e'));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomName = MatrixService.cleanName(
      MatrixService().getResolvedDisplayName(_call.room),
    );
    final title = roomName.trim().isEmpty ? 'Group' : roomName.trim();

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_closing) {
          VoipService().rejectGroupCall(_call);
        }
      },
      child: Scaffold(
        backgroundColor: kBlack,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    const SizedBox(height: 54),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Incoming group ${_isVideoCall ? 'video' : 'voice'} call',
                      style: GoogleFonts.inter(
                        color: kLightGrey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: StoryAvatar(
                          userName: title,
                          avatarUrl: _call.room.avatar?.toString(),
                          size: 142,
                          fallbackIcon: Icons.group,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 34),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _SwipeGroupCallActionButton(
                            icon: Icons.call_end,
                            label: 'Decline',
                            gradientColors: const [
                              Color(0xFFFF6961),
                              Color(0xFFFF3B30),
                              Color(0xFFC21D1D),
                            ],
                            iconColor: kWhite,
                            disabled: _busy,
                            onCompleted: _decline,
                          ),
                          _SwipeGroupCallActionButton(
                            icon: _isVideoCall ? Icons.videocam : Icons.call,
                            label: 'Answer',
                            gradientColors: const [
                              Color(0xFF34D875),
                              Color(0xFF22C55E),
                              Color(0xFF15803D),
                            ],
                            iconColor: kWhite,
                            disabled: _busy,
                            onCompleted: _answer,
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
      ),
    );
  }
}

class _SwipeGroupCallActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<Color> gradientColors;
  final Color iconColor;
  final bool disabled;
  final Future<void> Function() onCompleted;

  const _SwipeGroupCallActionButton({
    required this.icon,
    required this.label,
    required this.gradientColors,
    required this.iconColor,
    required this.disabled,
    required this.onCompleted,
  });

  @override
  State<_SwipeGroupCallActionButton> createState() =>
      _SwipeGroupCallActionButtonState();
}

class _SwipeGroupCallActionButtonState
    extends State<_SwipeGroupCallActionButton>
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
    if (_completed || widget.disabled) return;
    setState(() {
      _completed = true;
      _dragProgress = 1.0;
    });
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.disabled ? 0.55 : 1,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (_completed || widget.disabled) return;
          setState(() {
            _dragProgress = (_dragProgress - details.delta.dy / _maxLift).clamp(
              0.0,
              1.0,
            );
          });
        },
        onVerticalDragEnd: (_) {
          if (_completed || widget.disabled) return;
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
                offset: Offset(0, -_dragProgress * _maxLift),
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
      ),
    );
  }
}
