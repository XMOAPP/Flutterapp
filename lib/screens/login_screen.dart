import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/otp_service.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'otp_screen.dart';

// ─── Country code data ──────────────────────────────────────────────────────
class _Country {
  final String name;
  final String flag;
  final String code;
  const _Country(this.name, this.flag, this.code);
}

const _countries = [
  _Country('India', '🇮🇳', '+91'),
  _Country('United States', '🇺🇸', '+1'),
  _Country('United Kingdom', '🇬🇧', '+44'),
  _Country('UAE', '🇦🇪', '+971'),
  _Country('Singapore', '🇸🇬', '+65'),
  _Country('Australia', '🇦🇺', '+61'),
  _Country('Canada', '🇨🇦', '+1'),
];

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
  
  bool _isRegisterMode = true; // Default to register based on user request
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  _Country _selectedCountry = _countries.first;

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
      final fullPhone = '${_selectedCountry.code}${_phoneCtrl.text.trim()}';
      final email = _emailCtrl.text.trim();
      
      // We set state to loading so the button shows a spinner while talking to Firebase
      setState(() => _obscurePassword = _obscurePassword); // just to trigger rebuild with provider isLoading state? No, we need local state.
      // Actually, we can just use a local bool if we wanted, but let's just do it inline.
      showDialog(
        context: context, 
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: kLimeGreen))
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  // ── Logo ──────────────────────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: kLimeGreen,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Center(
                            child: Text(
                              'X',
                              style: GoogleFonts.cormorantGaramond(
                                color: kBlack,
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'XMO',
                          style: GoogleFonts.cormorantGaramond(
                            color: kWhite,
                            fontSize: 32,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isRegisterMode
                              ? 'Create your account'
                              : 'Sign in to continue',
                          style: GoogleFonts.inter(
                            color: kLightGrey,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Username ─────────────────────────────────────────────
                  _label('Username'),
                  const SizedBox(height: 8),
                  _textField(
                    controller: _usernameCtrl,
                    hint: 'e.g. alice',
                    icon: Icons.person_outline,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  if (_isRegisterMode) ...[
                    // ── Email ──────────────────────────────────────────────
                    _label('Email Address'),
                    const SizedBox(height: 8),
                    _textField(
                      controller: _emailCtrl,
                      hint: 'you@example.com',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!RegExp(r'^[\w\.\-]+@[\w\-]+\.\w{2,}$').hasMatch(v.trim())) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Phone ──────────────────────────────────────────────
                    _label('Phone Number'),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CountryPicker(
                          selected: _selectedCountry,
                          onChanged: (c) => setState(() => _selectedCountry = c),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '9876543210',
                              hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
                              filled: true,
                              fillColor: kDarkGrey,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLimeGreen, width: 1.5)),
                              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6))),
                              focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6), width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            ),
                            validator: (v) => (v == null || v.trim().length < 6) ? 'Valid phone required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Password ─────────────────────────────────────────────
                  _label('Password'),
                  const SizedBox(height: 8),
                  _textField(
                    controller: _passwordCtrl,
                    hint: '••••••••',
                    icon: Icons.lock_outline,
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
                    const SizedBox(height: 16),
                    // ── Confirm Password ────────────────────────────────────
                    _label('Confirm Password'),
                    const SizedBox(height: 8),
                    _textField(
                      controller: _confirmCtrl,
                      hint: '••••••••',
                      icon: Icons.lock_outline,
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

                  const SizedBox(height: 12),

                  // ── Error ─────────────────────────────────────────────────
                  if (provider.error != null && !isLoading && !_isRegisterMode) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(provider.error!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // ── Submit Button ─────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kLimeGreen,
                        foregroundColor: kBlack,
                        disabledBackgroundColor: kLimeGreen.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: isLoading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: kBlack))
                          : Text(
                              _isRegisterMode ? 'Verify Email & Register' : 'Sign In',
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Toggle Login / Register ───────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isRegisterMode = !_isRegisterMode;
                        provider.error; // dismiss errors
                      }),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(fontSize: 14, color: kLightGrey),
                          children: [
                            TextSpan(text: _isRegisterMode ? 'Already have an account? ' : "Don't have an account? "),
                            TextSpan(text: _isRegisterMode ? 'Sign In' : 'Register', style: GoogleFonts.inter(color: kLimeGreen, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(color: kWhite, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
        prefixIcon: Icon(icon, color: kLightGrey, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: kDarkGrey,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLimeGreen, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

// ─── Country Picker ─────────────────────────────────────────────────────────

class _CountryPicker extends StatelessWidget {
  final _Country selected;
  final ValueChanged<_Country> onChanged;

  const _CountryPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showModalBottomSheet<_Country>(
          context: context,
          backgroundColor: kDarkerGrey,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => _CountrySheet(selected: selected),
        );
        if (result != null) onChanged(result);
      },
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: kDarkGrey,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selected.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Text(selected.code, style: GoogleFonts.inter(color: kWhite, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: kLightGrey, size: 18),
          ],
        ),
      ),
    );
  }
}

class _CountrySheet extends StatelessWidget {
  final _Country selected;
  const _CountrySheet({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: kDarkGrey, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('Select Country', style: GoogleFonts.inter(color: kWhite, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ..._countries.map(
          (c) => ListTile(
            leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
            title: Text(c.name, style: GoogleFonts.inter(color: kWhite, fontSize: 14)),
            trailing: Text(c.code, style: GoogleFonts.inter(color: c == selected ? kLimeGreen : kLightGrey, fontWeight: FontWeight.w600)),
            selected: c == selected,
            onTap: () => Navigator.pop(context, c),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
