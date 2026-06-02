import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import 'auth_choice_screen.dart';
import 'home_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OPTIMIZED SPLASH SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialScreen());
  }

  void _openInitialScreen() {
    if (!mounted) return;
    final isLoggedIn = context.read<MatrixProvider>().isLoggedIn;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            isLoggedIn ? const HomeScreen() : const AuthChoiceScreen(),
        transitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image - Use RepaintBoundary
          RepaintBoundary(
            child: Image.asset(
              'assets/images/splash_bg.png',
              fit: BoxFit.cover,
              // Add cacheWidth/cacheHeight for memory optimization
              cacheWidth: MediaQuery.of(context).size.width.toInt() * 2,
            ),
          ),

          // Dark overlay - const
          const _DarkOverlay(),

          const Positioned(
            bottom: 76,
            left: 50,
            right: 50,
            child: _SplashLogo(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DARK OVERLAY - Extracted as const widget
// ═══════════════════════════════════════════════════════════════════════════

class _DarkOverlay extends StatelessWidget {
  const _DarkOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.2),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPLASH LOGO - Optimized with RepaintBoundary
// ═══════════════════════════════════════════════════════════════════════════

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // App Logo / Name - Cache text style
          Text('XMO', style: _logoTextStyle),
        ],
      ),
    );
  }

  // Cache text styles
  static final _logoTextStyle = GoogleFonts.cormorantGaramond(
    color: Colors.white,
    fontSize: 32,
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w500,
    letterSpacing: 3.0,
  );
}
