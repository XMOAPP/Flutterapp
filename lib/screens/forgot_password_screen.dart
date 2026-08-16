import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../providers/matrix_provider.dart';
import '../services/matrix_sso_service.dart';
import '../services/otp_service.dart';
import '../theme.dart';
import 'home_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _step = 0;
  bool _busy = false;
  bool _showPassword = false;
  bool _showConfirm = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _codeCtrl.addListener(_handleCodeChanged);
  }

  @override
  void dispose() {
    _codeCtrl.removeListener(_handleCodeChanged);
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _handleCodeChanged() {
    if (_step == 1 && mounted) setState(() {});
  }

  bool get _canContinue {
    if (_busy) return false;
    if (_step == 1) return RegExp(r'^\d{6}$').hasMatch(_codeCtrl.text.trim());
    return true;
  }

  Future<void> _continue() async {
    setState(() {
      _error = null;
      _message = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      if (_step == 0) {
        final error = await OtpService().startPasswordReset(
          username: _usernameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
        );
        if (!mounted) return;
        if (error != null) {
          setState(() => _error = error);
          return;
        }
        setState(() {
          _step = 1;
          _message =
              'If this email matches the account, a reset code was sent.';
        });
      } else if (_step == 1) {
        setState(() => _step = 2);
      } else if (_step == 2) {
        final error = await OtpService().completePasswordReset(
          username: _usernameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          otp: _codeCtrl.text.trim(),
          newPassword: _passwordCtrl.text,
        );
        if (!mounted) return;
        if (error != null) {
          setState(() => _error = error);
          return;
        }
        setState(() => _step = 3);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _message = null;
      _busy = true;
    });
    final error = await OtpService().startPasswordReset(
      username: _usernameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _message = error == null ? 'Reset code sent again.' : null;
    });
  }

  Future<void> _openTwoStepSetup() async {
    if (!AppConfig.isSsoLoginConfigured ||
        AppConfig.mfaSetupUrl.trim().isEmpty) {
      setState(() {
        _error = 'Two-step verification is not available yet.';
      });
      return;
    }

    final opened = await launchUrl(
      Uri.parse(AppConfig.mfaSetupUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) return;
    setState(() {
      _error = 'Could not open two-step verification. Please try again.';
    });
  }

  Future<void> _signInAfterRecovery() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await MatrixSsoService.instance.startSignIn();
      if (!mounted) return;
      final signedIn = await context.read<MatrixProvider>().loginWithSsoToken(
        token,
      );
      if (!mounted) return;
      if (!signedIn) {
        setState(() {
          _error =
              context.read<MatrixProvider>().error ??
              'Secure sign-in could not be completed.';
        });
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on MatrixSsoException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final horizontalPadding = (size.width * 0.08).clamp(20.0, 28.0).toDouble();

    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            24 + viewInsets.bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Text(
                  'Reset password',
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: kLightGrey,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 28),
                ..._fieldsForStep(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _StatusText(text: _error!, color: Colors.redAccent),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  _StatusText(text: _message!, color: kLightGrey),
                ],
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _step == 3
                          ? (_busy
                                ? null
                                : (AppConfig.oidcOnlyAuthentication
                                      ? _signInAfterRecovery
                                      : _openTwoStepSetup))
                          : (_canContinue ? _continue : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kWhite,
                        foregroundColor: kBlack,
                        disabledBackgroundColor: const Color(0xFF2C2C2E),
                        disabledForegroundColor: kLightGrey,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: kBlack,
                              ),
                            )
                          : Text(
                              _step == 3
                                  ? (AppConfig.oidcOnlyAuthentication
                                        ? 'Continue to login'
                                        : 'Set Up Authenticator')
                                  : _buttonText,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
                if (_step == 1) ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _busy ? null : _resend,
                    child: Text(
                      'Resend code',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (_step == 3) ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text(
                      'Back to login',
                      style: GoogleFonts.inter(
                        color: kLimeGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    if (_step == 0) {
      return 'Enter your username and verified email address.';
    }
    if (_step == 1) {
      return 'Enter the 6-digit reset code sent to your email.';
    }
    if (_step == 3) {
      return AppConfig.oidcOnlyAuthentication
          ? 'Your password was updated. Continue to sign in.'
          : 'Your password was updated. Set up an authenticator now to add two-step verification.';
    }
    return 'Choose a new password for your XMO account.';
  }

  String get _buttonText {
    if (_step == 0) return 'Send Reset Code';
    if (_step == 1) return 'Continue';
    return 'Change Password';
  }

  List<Widget> _fieldsForStep() {
    if (_step == 0) {
      return [
        _ResetTextField(
          controller: _usernameCtrl,
          label: 'Username',
          hint: 'kiran',
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'Required';
            if (!RegExp(r'^[a-zA-Z0-9._=\-/]+$').hasMatch(value.trim())) {
              return 'Invalid username';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _ResetTextField(
          controller: _emailCtrl,
          label: 'Email Address',
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) return 'Email is required';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
              return 'Enter a valid email';
            }
            return null;
          },
        ),
      ];
    }
    if (_step == 1) {
      return [
        _ResetCodeBoxesField(
          controller: _codeCtrl,
          validator: (value) {
            final code = value?.trim() ?? '';
            if (!RegExp(r'^\d{6}$').hasMatch(code)) {
              return 'Enter the 6-digit code';
            }
            return null;
          },
        ),
      ];
    }
    if (_step == 2) {
      return [
        _ResetTextField(
          controller: _passwordCtrl,
          label: 'New Password',
          hint: 'Password',
          obscure: !_showPassword,
          suffixIcon: IconButton(
            icon: Icon(
              _showPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: kLightGrey,
            ),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
          validator: (value) {
            if ((value ?? '').length < 6) return 'Min 6 characters';
            return null;
          },
        ),
        const SizedBox(height: 14),
        _ResetTextField(
          controller: _confirmCtrl,
          label: 'Confirm Password',
          hint: 'Password',
          obscure: !_showConfirm,
          suffixIcon: IconButton(
            icon: Icon(
              _showConfirm
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: kLightGrey,
            ),
            onPressed: () => setState(() => _showConfirm = !_showConfirm),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Required';
            if (value != _passwordCtrl.text) return 'Passwords do not match';
            return null;
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Encrypted chat history still requires your recovery key after reinstall.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ];
    }

    return [
      const Icon(Icons.verified_user_outlined, color: kLimeGreen, size: 44),
      const SizedBox(height: 16),
      Text(
        'Password updated',
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        AppConfig.oidcOnlyAuthentication
            ? 'Continue to securely sign in with your new password.'
            : 'Use the same username and new password to continue in your secure account.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 13, height: 1.35),
      ),
    ];
  }
}

class _ResetTextField extends StatelessWidget {
  const _ResetTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.obscure = false,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            letterSpacing: 1.4,
            color: kLightGrey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          cursorColor: kWhite,
          style: GoogleFonts.inter(color: kWhite, fontSize: 14),
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF2C2C2E),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(25),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(25),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(25),
              borderSide: const BorderSide(color: kWhite, width: 1),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(25),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(25),
              borderSide: const BorderSide(color: Colors.redAccent, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResetCodeBoxesField extends StatefulWidget {
  const _ResetCodeBoxesField({required this.controller, this.validator});

  final TextEditingController controller;
  final String? Function(String?)? validator;

  @override
  State<_ResetCodeBoxesField> createState() => _ResetCodeBoxesFieldState();
}

class _ResetCodeBoxesFieldState extends State<_ResetCodeBoxesField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleCodeChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleCodeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleCodeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: (_) => widget.validator?.call(widget.controller.text),
      builder: (field) {
        final code = widget.controller.text;
        return Column(
          children: [
            Text(
              'RESET CODE',
              style: GoogleFonts.inter(
                fontSize: 11,
                letterSpacing: 1.4,
                color: kLightGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const count = 6;
                  final gap = constraints.maxWidth < 300 ? 6.0 : 8.0;
                  final availableForBoxes =
                      constraints.maxWidth - (gap * (count - 1));
                  final boxWidth = (availableForBoxes / count).clamp(
                    32.0,
                    46.0,
                  );
                  final boxHeight = (boxWidth * 1.22).clamp(44.0, 56.0);
                  final complete = code.length == count;

                  return Center(
                    child: SizedBox(
                      width: (boxWidth * count) + (gap * (count - 1)),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(count, (index) {
                              final digit = index < code.length
                                  ? code[index]
                                  : '';
                              return SizedBox(
                                width: boxWidth,
                                height: boxHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2C2C2E),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: complete
                                          ? kWhite
                                          : kWhite.withValues(alpha: 0.12),
                                      width: complete ? 1 : 0.8,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      digit,
                                      style: GoogleFonts.inter(
                                        color: kWhite,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          Opacity(
                            opacity: 0,
                            child: TextField(
                              controller: widget.controller,
                              focusNode: _focusNode,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              onChanged: (_) =>
                                  field.didChange(widget.controller.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (field.hasError) ...[
              const SizedBox(height: 6),
              Text(
                field.errorText!,
                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(color: color, fontSize: 13, height: 1.35),
    );
  }
}
