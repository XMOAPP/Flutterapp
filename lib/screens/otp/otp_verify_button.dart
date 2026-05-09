import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/matrix_provider.dart';
import '../../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OTP VERIFY BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class OtpVerifyButton extends StatelessWidget {
  final bool isVerifying;
  final String enteredCode;
  final int otpLength;
  final VoidCallback onVerify;

  const OtpVerifyButton({
    super.key,
    required this.isVerifying,
    required this.enteredCode,
    required this.otpLength,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MatrixProvider>();

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (isVerifying || enteredCode.length < otpLength)
            ? null
            : onVerify,
        style: ElevatedButton.styleFrom(
          backgroundColor: kLimeGreen,
          foregroundColor: kBlack,
          disabledBackgroundColor: kDarkGrey,
          disabledForegroundColor: kLightGrey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: isVerifying
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: kBlack),
              )
            : provider.isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kBlack),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Connecting…',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Verify & Continue',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
      ),
    );
  }
}
