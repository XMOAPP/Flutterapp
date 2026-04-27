import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/otp_service.dart';
import '../theme.dart';
import 'home_screen.dart';

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
  final List<FocusNode> _foci =
      List.generate(_otpLength, (_) => FocusNode());

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

  // ─── Timer ──────────────────────────────────────────────────────────────────

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'OTP resent to ${widget.email}',
              style: GoogleFonts.inter(color: kBlack),
            ),
            backgroundColor: kBlue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      },
      onError: (err) {
        setState(() => _error = err);
      }
    );
  }

  // ─── OTP box input handling ─────────────────────────────────────────────────

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Handle paste — spread digits across boxes
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < _otpLength && i < digits.length; i++) {
        _ctrs[i].text = digits[i];
      }
      final nextEmpty = digits.length < _otpLength ? digits.length : _otpLength - 1;
      _foci[nextEmpty].requestFocus();
      _tryAutoSubmit();
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _foci[index + 1].requestFocus();
    }
    _tryAutoSubmit();
  }

  void _onKeyPress(int index, RawKeyEvent event) {
    if (event is RawKeyDownEvent &&
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

  // ─── Verify ─────────────────────────────────────────────────────────────────

  Future<void> _verify(String code) async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final isValid = await OtpService().verifyOtp(code);

    if (!isValid) {
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

    final provider = context.read<MatrixProvider>();
    bool ok;
    if (widget.isRegister) {
      ok = await provider.register(widget.username!, widget.password!);
      // Note: In a real app, you would also save the phone & email mapping to your backend here.
    } else {
      ok = await provider.loginWithPhone(widget.phone, widget.email);
    }

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (ok) {
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
      setState(() => _error = provider.error ?? 'Authentication failed.');
    }
  }

  String get _enteredCode => _ctrs.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MatrixProvider>();

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

              // ── Header ─────────────────────────────────────────────────────
              Text(
                'Verify your email',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
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
                  color: kBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),

              const SizedBox(height: 40),

              // ── OTP Boxes ──────────────────────────────────────────────────
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_shakeAnim.value, 0),
                  child: child,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_otpLength, (i) {
                    final isActive = _foci[i].hasFocus;
                    final filled = _ctrs[i].text.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 46,
                        height: 56,
                        decoration: BoxDecoration(
                          color: filled
                              ? kBlue.withValues(alpha: 0.12)
                              : kDarkGrey,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _error != null
                                ? Colors.red.withValues(alpha: 0.7)
                                : isActive
                                    ? kBlue
                                    : filled
                                        ? kBlue.withValues(alpha: 0.5)
                                        : Colors.white
                                            .withValues(alpha: 0.06),
                            width: isActive ? 2 : 1.5,
                          ),
                        ),
                        child: RawKeyboardListener(
                          focusNode: FocusNode(),
                          onKey: (e) => _onKeyPress(i, e),
                          child: TextField(
                            controller: _ctrs[i],
                            focusNode: _foci[i],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: i == 0 ? _otpLength : 1,
                            // Allow paste on first box
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
                            onChanged: (v) => _onDigitChanged(i, v),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 16),

              // ── Error ──────────────────────────────────────────────────────
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

              // ── Timer / Resend ─────────────────────────────────────────────
              _remaining > 0
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Didn't receive the code? ",
                          style: GoogleFonts.inter(
                              color: kLightGrey, fontSize: 13),
                        ),
                        Text(
                          '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}',
                          style: GoogleFonts.inter(
                            color: kBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : GestureDetector(
                      onTap: _resend,
                      child: Text(
                        'Resend OTP',
                        style: GoogleFonts.inter(
                          color: kBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: kBlue,
                        ),
                      ),
                    ),

              const SizedBox(height: 36),

              // ── Verify button ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed:
                      (_isVerifying || _enteredCode.length < _otpLength)
                          ? null
                          : () => _verify(_enteredCode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBlue,
                    foregroundColor: kBlack,
                    disabledBackgroundColor:
                        kDarkGrey,
                    disabledForegroundColor: kLightGrey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isVerifying
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
              ),

              const SizedBox(height: 40),

              // ── Phone info ────────────────────────────────────────────────
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
