import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/matrix_provider.dart';
import '../services/otp_service.dart';
import '../theme.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'otp_screen.dart';
import 'login/login_form_fields.dart';
import 'login/login_buttons.dart';
import 'login/error_display.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOGIN SCREEN - Refactored
// ═══════════════════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isRegisterMode = false;
  String? _usernameError;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _usernameError = null);
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<MatrixProvider>();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (_isRegisterMode) {
      final fullPhone = _phoneCtrl.text.trim();
      final email = _emailCtrl.text.trim();

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: kWhite),
        ),
      );

      bool usernameAvailable;
      try {
        usernameAvailable =
            await provider.service.isUsernameAvailable(username);
      } catch (e) {
        if (!mounted) return;
        if (_isUsernameTakenError(e)) {
          _showUsernameTakenError(closeDialog: true);
          return;
        }
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (!mounted) return;
      if (!usernameAvailable) {
        Navigator.pop(context);
        setState(() => _usernameError = 'Username already taken.');
        _formKey.currentState?.validate();
        return;
      }

      if (!AppConfig.requireEmailOtp) {
        final ok = await provider.register(username, password);
        if (!mounted) return;
        Navigator.pop(context);

        if (ok) {
          await OtpService().linkPasswordResetEmail(
            username: username,
            email: email,
          );
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else if (_isUsernameTakenError(provider.error)) {
          _showUsernameTakenError();
        }
        return;
      }

      await OtpService().sendEmailOtp(
        email: email,
        onCodeSent: () async {
          if (!mounted) return;
          Navigator.pop(context);
          final result = await Navigator.push<Map<String, String>>(
            context,
            MaterialPageRoute(
              builder: (_) => OtpScreen(
                phone: fullPhone,
                email: email,
                isRegister: true,
                username: username,
                password: password,
              ),
            ),
          );
          if (!mounted) return;
          if (result?['usernameError'] != null) {
            _showUsernameTakenError();
          }
        },
        onError: (err) {
          if (!mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err),
              backgroundColor: Colors.red,
            ),
          );
        },
      );
    } else {
      final ok = await provider.login(username, password);
      if (ok && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  bool _isUsernameTakenError(Object? error) {
    final raw = error?.toString();
    if (raw == null) return false;
    return raw.contains('M_USER_IN_USE') ||
        raw.toLowerCase().contains('username already taken') ||
        raw.toLowerCase().contains('user id already taken');
  }

  void _showUsernameTakenError({bool closeDialog = false}) {
    if (closeDialog) {
      Navigator.pop(context);
    }
    setState(() => _usernameError = 'Username already taken.');
    _formKey.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final horizontalPadding =
        (mediaQuery.size.width * 0.08).clamp(20.0, 28.0).toDouble();

    return Scaffold(
      backgroundColor: kBlack,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              16 + mediaQuery.viewInsets.bottom,
            ),
            child: Form(
              key: _formKey,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      mediaQuery.size.height - mediaQuery.padding.vertical - 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: _isRegisterMode ? 12 : (isLandscape ? 20 : 80),
                    ),
                    _buildTitle(),
                    const SizedBox(height: 20),
                    UsernameField(
                      controller: _usernameCtrl,
                      externalError: _usernameError,
                      onChanged: () {
                        if (_usernameError != null) {
                          setState(() => _usernameError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_isRegisterMode) ...[
                      EmailField(controller: _emailCtrl),
                      const SizedBox(height: 12),
                      PhoneField(controller: _phoneCtrl),
                      const SizedBox(height: 12),
                    ],
                    PasswordField(controller: _passwordCtrl),
                    if (_isRegisterMode) ...[
                      const SizedBox(height: 12),
                      ConfirmPasswordField(
                        controller: _confirmCtrl,
                        passwordController: _passwordCtrl,
                      ),
                    ],
                    const SizedBox(height: 8),
                    LoginErrorDisplay(isRegisterMode: _isRegisterMode),
                    const SizedBox(height: 24),
                    SubmitButton(
                      isRegisterMode: _isRegisterMode,
                      onPressed: _submit,
                    ),
                    if (!_isRegisterMode) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Forgot password?',
                          style: GoogleFonts.inter(
                            color: kWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ToggleAuthModeButton(
                      isRegisterMode: _isRegisterMode,
                      onToggle: () => setState(() {
                        _isRegisterMode = !_isRegisterMode;
                        _usernameError = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Center(
      child: Text(
        _isRegisterMode ? 'Create your account' : 'Login to continue',
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
