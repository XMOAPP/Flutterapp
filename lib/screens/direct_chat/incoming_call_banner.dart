import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../services/matrix_service.dart';
import '../../services/voip_service.dart';
import '../../theme.dart';
import '../../widgets/story/story_avatar.dart';

class IncomingCallBanner extends StatefulWidget {
  const IncomingCallBanner({super.key});

  @override
  State<IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends State<IncomingCallBanner> {
  bool _busy = false;

  Future<void> _answer(CallSession session) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await VoipService().answerIncomingCall(session);
    } catch (e) {
      debugPrint('[IncomingCallBanner] Answer failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(CallSession session) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await VoipService().rejectIncomingCall(session);
    } catch (e) {
      debugPrint('[IncomingCallBanner] Reject failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinGroupCall(XmoGroupCall groupCall) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await VoipService().answerIncomingGroupCall(groupCall);
    } catch (e) {
      debugPrint('[IncomingCallBanner] Group join failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _dismissGroupCall(XmoGroupCall groupCall) {
    if (_busy) return;
    VoipService().dismissIncomingGroupCall(groupCall);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ValueListenableBuilder<CallSession?>(
          valueListenable: VoipService().incomingCall,
          builder: (context, session, _) {
            final call = session;
            final shouldShow =
                call != null &&
                call.direction == CallDirection.kIncoming &&
                call.state == CallState.kRinging &&
                !VoipService().pipMode.value;
            final visibleCall = shouldShow ? call : null;

            return IgnorePointer(
              ignoring: !shouldShow,
              child: AnimatedSlide(
                offset: shouldShow ? Offset.zero : const Offset(0, -1.4),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: shouldShow ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: visibleCall != null
                      ? _IncomingCallCard(
                          session: visibleCall,
                          busy: _busy,
                          onAnswer: () => _answer(visibleCall),
                          onReject: () => _reject(visibleCall),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
        ValueListenableBuilder<XmoGroupCall?>(
          valueListenable: VoipService().incomingGroupCall,
          builder: (context, groupCall, _) {
            final call = groupCall;
            final shouldShow = call != null && !VoipService().pipMode.value;
            final visibleCall = shouldShow ? call : null;
            return IgnorePointer(
              ignoring: !shouldShow,
              child: AnimatedSlide(
                offset: shouldShow ? Offset.zero : const Offset(0, -1.4),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: shouldShow ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: visibleCall != null
                      ? _IncomingGroupCallCard(
                          groupCall: visibleCall,
                          busy: _busy,
                          onJoin: () => _joinGroupCall(visibleCall),
                          onDismiss: () => _dismissGroupCall(visibleCall),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _IncomingCallCard extends StatelessWidget {
  final CallSession session;
  final bool busy;
  final VoidCallback onAnswer;
  final VoidCallback onReject;

  const _IncomingCallCard({
    required this.session,
    required this.busy,
    required this.onAnswer,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final title = MatrixService.cleanName(
      MatrixService().getResolvedDisplayName(session.room),
    );
    final displayName = title.trim().isEmpty ? 'Unknown' : title.trim();
    final isVideo = session.type == CallType.kVideo;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF262728),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: kBlack.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  StoryAvatar(
                    userName: displayName,
                    avatarUrl: session.room.avatar?.toString(),
                    size: 46,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: kWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isVideo ? 'Video call' : 'Voice call',
                          style: GoogleFonts.inter(
                            color: kWhite.withValues(alpha: 0.68),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CallBannerButton(
                    icon: Icons.call_end,
                    gradientColors: const [
                      Color(0xFFFF6A5F),
                      Color(0xFFFF3B30),
                      Color(0xFFB81712),
                    ],
                    iconColor: kWhite,
                    disabled: busy,
                    onTap: onReject,
                  ),
                  const SizedBox(width: 10),
                  _CallBannerButton(
                    icon: Icons.call,
                    gradientColors: const [
                      Color(0xFF34D399),
                      Color(0xFF22C55E),
                      Color(0xFF15803D),
                    ],
                    iconColor: kWhite,
                    disabled: busy,
                    onTap: onAnswer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallBannerButton extends StatelessWidget {
  final IconData icon;
  final List<Color> gradientColors;
  final Color iconColor;
  final bool disabled;
  final VoidCallback onTap;

  const _CallBannerButton({
    required this.icon,
    required this.gradientColors,
    required this.iconColor,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors[1].withValues(alpha: 0.25),
                blurRadius: 12,
              ),
            ],
          ),
          child: Icon(icon, color: iconColor, size: 23),
        ),
      ),
    );
  }
}

class _IncomingGroupCallCard extends StatelessWidget {
  final XmoGroupCall groupCall;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onDismiss;

  const _IncomingGroupCallCard({
    required this.groupCall,
    required this.busy,
    required this.onJoin,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final title = MatrixService.cleanName(
      MatrixService().getResolvedDisplayName(groupCall.room),
    );
    final displayName = title.trim().isEmpty ? 'Group' : title.trim();
    final isVideo = groupCall.type == XmoGroupCallType.video;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF262728),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: kBlack.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  StoryAvatar(
                    userName: displayName,
                    avatarUrl: groupCall.room.avatar?.toString(),
                    size: 46,
                    fallbackIcon: Icons.group,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: kWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isVideo ? 'Group video call' : 'Group voice call',
                          style: GoogleFonts.inter(
                            color: kWhite.withValues(alpha: 0.68),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CallBannerButton(
                    icon: Icons.call_end,
                    gradientColors: const [
                      Color(0xFFFF6A5F),
                      Color(0xFFFF3B30),
                      Color(0xFFB81712),
                    ],
                    iconColor: kWhite,
                    disabled: busy,
                    onTap: onDismiss,
                  ),
                  const SizedBox(width: 10),
                  _CallBannerButton(
                    icon: Icons.call,
                    gradientColors: const [
                      Color(0xFF34D399),
                      Color(0xFF22C55E),
                      Color(0xFF15803D),
                    ],
                    iconColor: kWhite,
                    disabled: busy,
                    onTap: onJoin,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
