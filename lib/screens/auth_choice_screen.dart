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
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
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
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

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
              return CustomPaint(painter: _OrbPainter(t), size: size);
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final shortestSide = MediaQuery.sizeOf(context).shortestSide;
                  final logoSize = (shortestSide * 0.44)
                      .clamp(120.0, 160.0)
                      .toDouble();
                  final horizontalPadding = (constraints.maxWidth * 0.08)
                      .clamp(20.0, 28.0)
                      .toDouble();
                  final buttonPadding = (constraints.maxWidth * 0.11)
                      .clamp(24.0, 40.0)
                      .toDouble();

                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // ── Logo ───────────────────────────────────────────────
                          Image.asset(
                            'assets/images/logo.png',
                            width: logoSize,
                            height: logoSize,
                          ),

                          const SizedBox(height: 0),

                          // ── Option buttons ───────────────────────────────────────
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: buttonPadding,
                            ),
                            child: Column(
                              children: [
                                _AuthButton(
                                  title: 'Sign Up / Login',
                                  onTap: _goToSignUp,
                                  isFirst: true,
                                ),
                                const SizedBox(height: 16),
                                _AuthButton(
                                  title: 'Connect Wallet',
                                  onTap: _goToWallet,
                                  isFirst: false,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
  final String title;
  final VoidCallback onTap;
  final bool isFirst;

  const _AuthButton({
    required this.title,
    required this.onTap,
    required this.isFirst,
  });

  @override
  State<_AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<_AuthButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // First button: white, second button: grey
    final bgColor = widget.isFirst ? kWhite : const Color(0xFF2C2C2E);
    final textColor = widget.isFirst ? kBlack : kWhite;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(30),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: bgColor.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              widget.title,
              style: GoogleFonts.inter(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
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
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
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
