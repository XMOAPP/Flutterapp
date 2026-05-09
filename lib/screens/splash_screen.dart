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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward().then((_) {
      if (!mounted) return;
      final isLoggedIn = context.read<MatrixProvider>().isLoggedIn;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              isLoggedIn ? const HomeScreen() : const AuthChoiceScreen(),
          transitionDuration: const Duration(milliseconds: 800),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

          // Progress Bar and Text at the bottom
          Positioned(
            bottom: 40,
            left: 50,
            right: 50,
            child: AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                final percent = (_progressAnimation.value * 100).toInt();
                return _ProgressContent(
                  progress: _progressAnimation.value,
                  percent: percent,
                );
              },
            ),
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
// PROGRESS CONTENT - Optimized with RepaintBoundary
// ═══════════════════════════════════════════════════════════════════════════

class _ProgressContent extends StatelessWidget {
  final double progress;
  final int percent;

  const _ProgressContent({
    required this.progress,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // App Logo / Name - Cache text style
          Text('XMO', style: _logoTextStyle),
          const SizedBox(height: 12),
          // Progress bar
          SizedBox(
            height: 1.5,
            child: Stack(
              children: [
                // Background line
                Container(
                  width: double.infinity,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                // Foreground line (progress)
                FractionallySizedBox(
                  widthFactor: progress,
                  alignment: Alignment.centerLeft,
                  child: Container(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Percentage text
          Text('$percent%', style: _percentTextStyle),
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

  static final _percentTextStyle = GoogleFonts.inter(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 2.0,
  );
}
