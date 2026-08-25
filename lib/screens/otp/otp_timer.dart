import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OTP TIMER & RESEND
// ═══════════════════════════════════════════════════════════════════════════

class OtpTimer extends StatelessWidget {
  final int remaining;
  final VoidCallback onResend;

  const OtpTimer({super.key, required this.remaining, required this.onResend});

  @override
  Widget build(BuildContext context) {
    if (remaining > 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Didn't receive the code? ",
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
          ),
          Text(
            '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: onResend,
      child: Text(
        'Resend OTP',
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
