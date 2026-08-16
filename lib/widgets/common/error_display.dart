import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xmo/utils/user_facing_error.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SHARED ERROR DISPLAY WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ErrorDisplay extends StatelessWidget {
  final String? error;
  final EdgeInsets padding;

  const ErrorDisplay({
    super.key,
    required this.error,
    this.padding = const EdgeInsets.only(top: 6),
  });

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(safeUserFacingText(error!), style: _errorTextStyle),
            ),
          ],
        ),
      ),
    );
  }

  static final _errorTextStyle = GoogleFonts.inter(
    color: Colors.redAccent,
    fontSize: 12,
  );
}
