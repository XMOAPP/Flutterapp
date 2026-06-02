import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../services/matrix_service.dart';
import '../../services/voip_service.dart';
import '../../theme.dart';
import '../../widgets/story/story_avatar.dart';
import 'group_call_screen.dart';

class IncomingGroupCallScreen extends StatefulWidget {
  final GroupCall groupCall;

  const IncomingGroupCallScreen({
    super.key,
    required this.groupCall,
  });

  @override
  State<IncomingGroupCallScreen> createState() =>
      _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState extends State<IncomingGroupCallScreen> {
  StreamSubscription? _stateSub;
  bool _busy = false;
  bool _closing = false;

  GroupCall get _call => widget.groupCall;
  bool get _isVideoCall => _call.type == GroupCallType.Video;

  @override
  void initState() {
    super.initState();
    VoipService().enterFullscreenCallRoute();
    _stateSub = _call.onGroupCallState.stream.listen((state) {
      if (state == GroupCallState.Ended && mounted && !_closing) {
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
      await VoipService().answerIncomingGroupCall(
        _call,
        openCallScreen: false,
      );
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
      _showError('Unable to join call: $e');
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
      _showError('Unable to decline call: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
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
                          _IncomingGroupCallAction(
                            icon: Icons.call_end,
                            label: 'Decline',
                            gradientColors: const [
                              Color(0xFFFF6961),
                              Color(0xFFFF3B30),
                              Color(0xFFC21D1D),
                            ],
                            labelColor: const Color(0xFFFF5B55),
                            disabled: _busy,
                            onTap: _decline,
                          ),
                          _IncomingGroupCallAction(
                            icon: _isVideoCall ? Icons.videocam : Icons.call,
                            label: 'Answer',
                            gradientColors: const [
                              Color(0xFF34D875),
                              Color(0xFF22C55E),
                              Color(0xFF15803D),
                            ],
                            labelColor: kWhite,
                            disabled: _busy,
                            onTap: _answer,
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

class _IncomingGroupCallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradientColors;
  final Color labelColor;
  final bool disabled;
  final VoidCallback onTap;

  const _IncomingGroupCallAction({
    required this.icon,
    required this.label,
    required this.gradientColors,
    required this.labelColor,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors[1].withValues(alpha: 0.36),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(icon, color: kWhite, size: 31),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                color: labelColor,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
