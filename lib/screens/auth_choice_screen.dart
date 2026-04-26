import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'wallet_auth_screen.dart';

class AuthChoiceScreen extends StatefulWidget {
  const AuthChoiceScreen({super.key});

  @override
  State<AuthChoiceScreen> createState() => _AuthChoiceScreenState();
}

class _AuthChoiceScreenState extends State<AuthChoiceScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _goToSignUp() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  void _goToWallet() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WalletAuthScreen(),
        transitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: kBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Animated gradient orbs ───────────────────────────────────────
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) {
              final t = _bgCtrl.value;
              return CustomPaint(
                painter: _OrbPainter(t),
                size: size,
              );
            },
          ),

          // ── Dark overlay ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // ── Logo ───────────────────────────────────────────────
                    _Logo(),

                    const SizedBox(height: 20),

                    Text(
                      'The future of\nsecure messaging',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cormorantGaramond(
                        color: kWhite,
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Choose how you want to get started',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: kLightGrey,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),

                    const Spacer(flex: 3),

                    // ── Option buttons ───────────────────────────────────────
                    _AuthButton(
                      icon: Icons.mail_outline_rounded,
                      iconColor: kBlack,
                      bgColor: kLimeGreen,
                      title: 'Sign Up / Sign In',
                      onTap: _goToSignUp,
                    ),

                    const SizedBox(height: 16),

                    _AuthButton(
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: kWhite,
                      bgColor: const Color(0xFF6C63FF),
                      title: 'Connect Wallet',
                      onTap: _goToWallet,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),

                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Auth Button ────────────────────────────────────────────────────────────

class _AuthButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final VoidCallback onTap;
  final Gradient? gradient;

  const _AuthButton({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.onTap,
    this.gradient,
  });

  @override
  State<_AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<_AuthButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: widget.gradient == null ? widget.bgColor : null,
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.bgColor.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: widget.iconColor, size: 24),
              const SizedBox(width: 12),
              Text(
                widget.title,
                style: GoogleFonts.inter(
                  color: widget.iconColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animated Logo ─────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: kLimeGreen,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kLimeGreen.withValues(alpha: 0.35),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          'X',
          style: GoogleFonts.cormorantGaramond(
            color: kBlack,
            fontSize: 44,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

// ── Animated background orbs ─────────────────────────────────────────────

class _OrbPainter extends CustomPainter {
  final double t;
  _OrbPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    void drawOrb(Color color, double cx, double cy, double r) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.35), Colors.transparent],
        ).createShader(
            Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }

    final s1 = math.sin(t * math.pi * 2);
    final c1 = math.cos(t * math.pi * 2);

    drawOrb(
      const Color(0xFF6C63FF),
      size.width * 0.15 + s1 * 40,
      size.height * 0.2 + c1 * 30,
      size.width * 0.5,
    );
    drawOrb(
      const Color(0xFF3ECFCF),
      size.width * 0.85 - c1 * 30,
      size.height * 0.35 + s1 * 20,
      size.width * 0.45,
    );
    drawOrb(
      kLimeGreen,
      size.width * 0.5 + s1 * 20,
      size.height * 0.75,
      size.width * 0.35,
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}
