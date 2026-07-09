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
        children: [
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const maxBoxWidth = 46.0;
                const minBoxWidth = 32.0;
                const maxGap = 8.0;
                final count = controllers.length;
                final gap = constraints.maxWidth < 300 ? 6.0 : maxGap;
                final availableForBoxes =
                    constraints.maxWidth - (gap * (count - 1));
                final boxWidth = (availableForBoxes / count)
                    .clamp(minBoxWidth, maxBoxWidth)
                    .toDouble();
                final boxHeight = (boxWidth * 1.22).clamp(44.0, 56.0);
                final digitFontSize = boxWidth < 40 ? 18.0 : 22.0;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(count * 2 - 1, (position) {
                    if (position.isOdd) return SizedBox(width: gap);
                    final i = position ~/ 2;
                    final isActive = focusNodes[i].hasFocus;
                    final filled = controllers[i].text.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: boxWidth,
                      height: boxHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: error != null
                              ? Colors.red.withValues(alpha: 0.7)
                              : isActive
                                  ? kWhite
                                  : filled
                                      ? kWhite.withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: 0.06),
                          width: isActive ? 2 : 1.5,
                        ),
                      ),
                      child: KeyboardListener(
                        focusNode: FocusNode(),
                        onKeyEvent: (e) => onKeyPress(i, e),
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
                            fontSize: digitFontSize,
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
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
