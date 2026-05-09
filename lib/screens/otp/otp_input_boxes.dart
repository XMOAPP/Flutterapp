import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OTP INPUT BOXES
// ═══════════════════════════════════════════════════════════════════════════

class OtpInputBoxes extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final String? error;
  final Animation<double> shakeAnimation;
  final Function(int, String) onDigitChanged;
  final Function(int, KeyEvent) onKeyPress;

  const OtpInputBoxes({
    super.key,
    required this.controllers,
    required this.focusNodes,
    required this.error,
    required this.shakeAnimation,
    required this.onDigitChanged,
    required this.onKeyPress,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shakeAnimation,
      builder: (_, child) => Transform.translate(
        offset: Offset(shakeAnimation.value, 0),
        child: child,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(controllers.length, (i) {
          final isActive = focusNodes[i].hasFocus;
          final filled = controllers[i].text.isNotEmpty;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 56,
              decoration: BoxDecoration(
                color: filled
                    ? kLimeGreen.withValues(alpha: 0.12)
                    : kDarkGrey,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: error != null
                      ? Colors.red.withValues(alpha: 0.7)
                      : isActive
                          ? kLimeGreen
                          : filled
                              ? kLimeGreen.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.06),
                  width: isActive ? 2 : 1.5,
                ),
              ),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (e) {
                  if (e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.backspace &&
                      controllers[i].text.isEmpty &&
                      i > 0) {
                    focusNodes[i - 1].requestFocus();
                    controllers[i - 1].clear();
                  }
                },
                child: TextField(
                  controller: controllers[i],
                  focusNode: focusNodes[i],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: i == 0 ? controllers.length : 1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (v) => onDigitChanged(i, v),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
