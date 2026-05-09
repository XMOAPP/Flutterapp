import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

/// Bottom input bar for sending messages and attachments
class ChatInputBar extends StatelessWidget {
  final TextEditingController textController;
  final bool hasText;
  final bool uploading;
  final bool enabled;
  final String? disabledText;
  final VoidCallback onSend;
  final VoidCallback onShowAttachmentSheet;

  const ChatInputBar({
    super.key,
    required this.textController,
    required this.hasText,
    required this.uploading,
    this.enabled = true,
    this.disabledText,
    required this.onSend,
    required this.onShowAttachmentSheet,
  });

  @override
  Widget build(BuildContext context) {
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
            // Attachment button
            GestureDetector(
              onTap: uploading || !enabled ? null : onShowAttachmentSheet,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 4),
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
                    const Icon(
                      Icons.emoji_emotions_outlined,
                      color: kLightGrey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: textController,
                        enabled: enabled,
                        style: GoogleFonts.inter(color: kWhite, fontSize: 14),
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: hasText && enabled
                  ? GestureDetector(
                      key: const ValueKey('send'),
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
                    )
                  : const SizedBox(width: 8),
            ),
          ],
        ),
      ),
    );
  }
}
