import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/matrix_provider.dart';
import '../../theme.dart';

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: ElevatedButton(
          onPressed:
              (isVerifying || enteredCode.length < otpLength) ? null : onVerify,
          style: ElevatedButton.styleFrom(
            backgroundColor: kWhite,
            foregroundColor: kBlack,
            disabledBackgroundColor: const Color(0xFF2C2C2E),
            disabledForegroundColor: kLightGrey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            elevation: 0,
          ),
          child: isVerifying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: kBlack,
                  ),
                )
              : provider.isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kBlack,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Connecting...',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Verify & Continue',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
        ),
      ),
    );
  }
}
