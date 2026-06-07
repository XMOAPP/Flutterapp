import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/matrix_provider.dart';
import '../../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOGIN BUTTONS
// ═══════════════════════════════════════════════════════════════════════════

class SubmitButton extends StatelessWidget {
  final bool isRegisterMode;
  final VoidCallback onPressed;

  const SubmitButton({
    super.key,
    required this.isRegisterMode,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<MatrixProvider, bool>(
      selector: (_, provider) => provider.state == MatrixAuthState.loggingIn,
      builder: (context, isLoading, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: _buttonStyle,
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: kBlack,
                      ),
                    )
                  : Text(
                      isRegisterMode ? 'Verify Email & Register' : 'Login',
                      style: _buttonTextStyle,
                    ),
            ),
          ),
        );
      },
    );
  }

  static final _buttonStyle = ElevatedButton.styleFrom(
    backgroundColor: kWhite,
    foregroundColor: kBlack,
    disabledBackgroundColor: kWhite.withValues(alpha: 0.5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    elevation: 0,
  );

  static final _buttonTextStyle = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
}

class ToggleAuthModeButton extends StatelessWidget {
  final bool isRegisterMode;
  final VoidCallback onToggle;

  const ToggleAuthModeButton({
    super.key,
    required this.isRegisterMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onToggle,
        child: RichText(
          text: TextSpan(
            style: _toggleTextStyle,
            children: [
              TextSpan(
                text: isRegisterMode
                    ? 'Already have an account? '
                    : "Don't have an account? ",
              ),
              TextSpan(
                text: isRegisterMode ? 'Login' : 'Register',
                style: _toggleHighlightStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static final _toggleTextStyle = GoogleFonts.inter(
    fontSize: 12,
    color: kLightGrey,
  );

  static final _toggleHighlightStyle = GoogleFonts.inter(
    color: kWhite,
    fontWeight: FontWeight.w600,
  );
}
