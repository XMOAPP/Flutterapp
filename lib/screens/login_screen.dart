import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/otp_service.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'otp_screen.dart';

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
  
  bool _isRegisterMode = false; // Default to sign in mode
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
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
      
      // We set state to loading so the button shows a spinner while talking to Firebase
      setState(() => _obscurePassword = _obscurePassword); // just to trigger rebuild with provider isLoading state? No, we need local state.
      // Actually, we can just use a local bool if we wanted, but let's just do it inline.
      showDialog(
        context: context, 
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: kWhite))
      );
      
      await OtpService().sendEmailOtp(
        email: email,
        onCodeSent: () {
          Navigator.pop(context); // close loader
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => OtpScreen(
                phone: fullPhone,
                email: email,
                isRegister: true,
                username: username,
                password: password,
              ),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (_, anim, __, child) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              ),
            ),
          );
        },
        onError: (err) {
          Navigator.pop(context); // close loader
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
        }
      );
    } else {
      // Login: Straight to backend
      final ok = await provider.login(username, password);
      if (ok && mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MatrixProvider>();
    final isLoading = provider.state == MatrixAuthState.loggingIn;

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
                  
                  // ── Title ──────────────────────────────────────────────────
                  Center(
                    child: Text(
                      _isRegisterMode
                          ? 'Create your account'
                          : 'Sign in to continue',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Username ─────────────────────────────────────────────
                  _label('Username'),
                  const SizedBox(height: 6),
                  _textField(
                    controller: _usernameCtrl,
                    hint: 'e.g. alice',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),

                  if (_isRegisterMode) ...[
                    // ── Email ──────────────────────────────────────────────
                    _label('Email Address'),
                    const SizedBox(height: 6),
                    _textField(
                      controller: _emailCtrl,
                      hint: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!RegExp(r'^[\w\.\-]+@[\w\-]+\.\w{2,}$').hasMatch(v.trim())) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── Phone ──────────────────────────────────────────────
                    _label('Phone Number'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      cursorColor: kWhite,
                      style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '+91 9876543210',
                        hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
                        filled: true,
                        fillColor: kDarkGrey,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: const BorderSide(color: kWhite, width: 1)),
                        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6))),
                        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6), width: 2)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().length < 6) ? 'Valid phone required' : null,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Password ─────────────────────────────────────────────
                  _label('Password'),
                  const SizedBox(height: 6),
                  _textField(
                    controller: _passwordCtrl,
                    hint: '••••••••',
                    obscure: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: kLightGrey, size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                  ),

                  if (_isRegisterMode) ...[
                    const SizedBox(height: 12),
                    // ── Confirm Password ────────────────────────────────────
                    _label('Confirm Password'),
                    const SizedBox(height: 6),
                    _textField(
                      controller: _confirmCtrl,
                      hint: '••••••••',
                      obscure: _obscureConfirm,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: kLightGrey, size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (v != _passwordCtrl.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                  ],

                  const SizedBox(height: 8),

                  // ── Error ─────────────────────────────────────────────────
                  if (provider.error != null && !isLoading && !_isRegisterMode) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(provider.error!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // ── Submit Button ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kWhite,
                          foregroundColor: kBlack,
                          disabledBackgroundColor: kWhite.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 0,
                        ),
                        child: isLoading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: kBlack))
                            : Text(
                                _isRegisterMode ? 'Verify Email & Register' : 'Sign In',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Toggle Login / Register ───────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isRegisterMode = !_isRegisterMode;
                        provider.error; // dismiss errors
                      }),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(fontSize: 12, color: kLightGrey),
                          children: [
                            TextSpan(text: _isRegisterMode ? 'Already have an account? ' : "Don't have an account? "),
                            TextSpan(text: _isRegisterMode ? 'Sign In' : 'Register', style: GoogleFonts.inter(color: kWhite, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
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

  Widget _label(String text) => Center(
        child: Text(
          text.toUpperCase(),
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.8),
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      cursorColor: kWhite,
      style: GoogleFonts.inter(color: kWhite, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: kDarkGrey,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: const BorderSide(color: kWhite, width: 1)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6), width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
  }
}
