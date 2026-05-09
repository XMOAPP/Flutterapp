import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/otp_service.dart';
import '../theme.dart';
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

      await OtpService().sendEmailOtp(
        email: email,
        onCodeSent: () {
          if (!mounted) return;
          Navigator.pop(context);
          Navigator.push(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),
                  _buildTitle(),
                  const SizedBox(height: 20),
                  UsernameField(controller: _usernameCtrl),
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
                  const Spacer(),
                  SubmitButton(
                    isRegisterMode: _isRegisterMode,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 12),
                  ToggleAuthModeButton(
                    isRegisterMode: _isRegisterMode,
                    onToggle: () => setState(() => _isRegisterMode = !_isRegisterMode),
                  ),
                  const SizedBox(height: 12),
                ],
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
        _isRegisterMode ? 'Create your account' : 'Sign in to continue',
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
