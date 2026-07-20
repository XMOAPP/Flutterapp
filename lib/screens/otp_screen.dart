import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/otp_service.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'otp/otp_input_boxes.dart';
import 'otp/otp_timer.dart';
import 'otp/otp_verify_button.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OTP SCREEN - Refactored
// ═══════════════════════════════════════════════════════════════════════════

class OtpScreen extends StatefulWidget {
  final String phone;
  final String email;
  final bool isRegister;
  final String? username;
  final String? password;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.email,
    this.isRegister = false,
    this.username,
    this.password,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  static const int _otpLength = 6;
  static const int _countdownSecs = 60;

  final List<TextEditingController> _ctrs =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _foci = List.generate(_otpLength, (_) => FocusNode());

  int _remaining = _countdownSecs;
  Timer? _timer;
  bool _isVerifying = false;
  String? _error;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _ctrs) {
      c.dispose();
    }
    for (final f in _foci) {
      f.dispose();
    }
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _remaining = _countdownSecs);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining > 0) {
        setState(() => _remaining--);
      } else {
        _timer?.cancel();
      }
    });
  }

  void _resend() {
    for (final c in _ctrs) {
      c.clear();
    }
    _foci.first.requestFocus();
    setState(() => _error = null);

    OtpService().sendEmailOtp(
        email: widget.email,
        onCodeSent: () {
          _startTimer();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'OTP resent to ${widget.email}',
                style: GoogleFonts.inter(color: kBlack),
              ),
              backgroundColor: kWhite,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
        onError: (err) {
          if (!mounted) return;
          setState(() => _error = err);
        });
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < _otpLength && i < digits.length; i++) {
        _ctrs[i].text = digits[i];
      }
      final nextEmpty =
          digits.length < _otpLength ? digits.length : _otpLength - 1;
      _foci[nextEmpty].requestFocus();
      _tryAutoSubmit();
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _foci[index + 1].requestFocus();
    }
    _tryAutoSubmit();
  }

  void _onKeyPress(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _ctrs[index].text.isEmpty &&
        index > 0) {
      _foci[index - 1].requestFocus();
      _ctrs[index - 1].clear();
    }
  }

  void _tryAutoSubmit() {
    final code = _ctrs.map((c) => c.text).join();
    if (code.length == _otpLength) {
      _verify(code);
    }
  }

  Future<void> _verify(String code) async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final isValid = await OtpService().verifyOtp(
      email: widget.email,
      code: code,
    );

    if (!isValid) {
      if (!mounted) return;
      setState(() {
        _error = 'Incorrect OTP. Please try again.';
        _isVerifying = false;
      });
      _shakeCtrl.forward(from: 0);
      for (final c in _ctrs) {
        c.clear();
      }
      _foci.first.requestFocus();
      return;
    }

    if (!mounted) return;
    final provider = context.read<MatrixProvider>();
    bool ok;
    if (widget.isRegister) {
      ok = await provider.register(widget.username!, widget.password!);
    } else {
      ok = await provider.loginWithPhone(widget.phone, widget.email);
    }

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (ok) {
      if (widget.isRegister && widget.username != null) {
        await OtpService().linkPasswordResetEmail(
          username: widget.username!,
          email: widget.email,
        );
        if (!mounted) return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (route) => false,
      );
    } else {
      final error = provider.error ?? 'Authentication failed.';
      if (widget.isRegister && _isUsernameTakenError(error)) {
        Navigator.pop(context, {'usernameError': 'Username already taken.'});
        return;
      }
      setState(() => _error = provider.error ?? 'Authentication failed.');
    }
  }

  String get _enteredCode => _ctrs.map((c) => c.text).join();

  bool _isUsernameTakenError(String error) {
    return error.contains('M_USER_IN_USE') ||
        error.toLowerCase().contains('username already taken') ||
        error.toLowerCase().contains('user id already taken');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Text(
                'Verify your email',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We sent a 6-digit code to',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                widget.email,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 40),
              OtpInputBoxes(
                controllers: _ctrs,
                focusNodes: _foci,
                error: _error,
                shakeAnimation: _shakeAnim,
                onDigitChanged: _onDigitChanged,
                onKeyPress: _onKeyPress,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _error!,
                        style: GoogleFonts.inter(
                            color: Colors.redAccent, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 28),
              OtpTimer(
                remaining: _remaining,
                onResend: _resend,
              ),
              const SizedBox(height: 36),
              OtpVerifyButton(
                isVerifying: _isVerifying,
                enteredCode: _enteredCode,
                otpLength: _otpLength,
                onVerify: () => _verify(_enteredCode),
              ),
              const SizedBox(height: 40),
              Center(
                child: Text(
                  'Wrong email? Go back to change it.',
                  style: GoogleFonts.inter(
                    color: kLightGrey.withValues(alpha: 0.5),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
