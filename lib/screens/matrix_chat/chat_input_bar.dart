import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import 'widgets/voice_waveform.dart';

/// Bottom input bar for sending messages and attachments.
class ChatInputBar extends StatelessWidget {
  final TextEditingController textController;
  final FocusNode? textFocusNode;
  final IconData emojiButtonIcon;
  final bool uploading;
  final bool enabled;
  final bool recording;
  final bool recordingPaused;
  final Duration recordingDuration;
  final List<double> recordingWaveform;
  final String? disabledText;
  final VoidCallback onSend;
  final VoidCallback onShowEmojiPicker;
  final VoidCallback? onTextFieldTap;
  final VoidCallback onShowAttachmentSheet;
  final VoidCallback onStartRecording;
  final VoidCallback onCancelRecording;
  final VoidCallback onToggleRecordingPause;
  final VoidCallback onStopAndSendRecording;

  const ChatInputBar({
    super.key,
    required this.textController,
    this.textFocusNode,
    this.emojiButtonIcon = Icons.emoji_emotions_outlined,
    required this.uploading,
    this.enabled = true,
    this.recording = false,
    this.recordingPaused = false,
    this.recordingDuration = Duration.zero,
    this.recordingWaveform = const [],
    this.disabledText,
    required this.onSend,
    required this.onShowEmojiPicker,
    this.onTextFieldTap,
    required this.onShowAttachmentSheet,
    required this.onStartRecording,
    required this.onCancelRecording,
    required this.onToggleRecordingPause,
    required this.onStopAndSendRecording,
  });

  @override
  Widget build(BuildContext context) {
    if (recording) {
      return _RecordingBar(
        duration: recordingDuration,
        paused: recordingPaused,
        waveform: recordingWaveform,
        onCancel: onCancelRecording,
        onTogglePause: onToggleRecordingPause,
        onSend: onStopAndSendRecording,
      );
    }

    final isNarrow = MediaQuery.sizeOf(context).width < 340;
    const actionSize = 40.0;
    final horizontalPadding = isNarrow ? 6.0 : 8.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
      decoration: const BoxDecoration(
        color: kDarkerGrey,
        border: Border(top: BorderSide(color: kDarkGrey, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: uploading || !enabled ? null : onShowAttachmentSheet,
              child: Container(
                width: actionSize,
                height: actionSize,
                margin: EdgeInsets.only(right: isNarrow ? 2 : 4),
                child: Icon(
                  Icons.add_circle_outline,
                  color: uploading || !enabled ? kMediumGrey : kLimeGreen,
                  size: 24,
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: kDarkGrey,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: enabled ? onShowEmojiPicker : null,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          emojiButtonIcon,
                          color: enabled ? kLightGrey : kMediumGrey,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: textController,
                        focusNode: textFocusNode,
                        readOnly: onTextFieldTap != null,
                        onTap: onTextFieldTap,
                        enabled: enabled,
                        style: GoogleFonts.inter(color: kWhite, fontSize: 17),
                        decoration: InputDecoration(
                          hintText: enabled
                              ? 'Message'
                              : disabledText ?? 'You cannot send messages',
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
                  ],
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: textController,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: hasText && enabled
                      ? GestureDetector(
                          key: const ValueKey('send'),
                          onTap: uploading || !enabled ? null : onSend,
                          child: Container(
                            width: actionSize,
                            height: actionSize,
                            margin: EdgeInsets.only(left: isNarrow ? 4 : 8),
                            decoration: BoxDecoration(
                              color: uploading || !enabled
                                  ? kDarkGrey
                                  : kLimeGreen,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.send_rounded,
                              color:
                                  uploading || !enabled ? kMediumGrey : kBlack,
                              size: 20,
                            ),
                          ),
                        )
                      : GestureDetector(
                          key: const ValueKey('record'),
                          onTap:
                              uploading || !enabled ? null : onStartRecording,
                          child: Container(
                            width: actionSize,
                            height: actionSize,
                            margin: EdgeInsets.only(left: isNarrow ? 4 : 8),
                            decoration: BoxDecoration(
                              color: uploading || !enabled
                                  ? kDarkGrey
                                  : const Color(0xFF2C2C2E),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.mic_rounded,
                              color: uploading || !enabled
                                  ? kMediumGrey
                                  : kLimeGreen,
                              size: 21,
                            ),
                          ),
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingBar extends StatelessWidget {
  final Duration duration;
  final bool paused;
  final List<double> waveform;
  final VoidCallback onCancel;
  final VoidCallback onTogglePause;
  final VoidCallback onSend;

  const _RecordingBar({
    required this.duration,
    required this.paused,
    required this.waveform,
    required this.onCancel,
    required this.onTogglePause,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final isNarrow = MediaQuery.sizeOf(context).width < 340;

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
            IconButton(
              tooltip: 'Cancel recording',
              onPressed: onCancel,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 54),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: kDarkGrey,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: onTogglePause,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: paused ? kLimeGreen : const Color(0xFF3B82F6),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (paused
                                      ? kLimeGreen
                                      : const Color(0xFF3B82F6))
                                  .withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          paused ? Icons.mic_rounded : Icons.pause_rounded,
                          color: paused ? kBlack : kWhite,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VoiceWaveform(
                        bars: waveform,
                        color: paused ? kMediumGrey : kLimeGreen,
                        inactiveColor: paused ? kMediumGrey : kLimeGreen,
                        progress: 1,
                        height: 30,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$minutes:$seconds',
                          style: GoogleFonts.inter(
                            color: kWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!isNarrow)
                          Text(
                            paused ? 'Paused' : 'Recording',
                            style: GoogleFonts.inter(
                              color: paused ? kMediumGrey : Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
}
