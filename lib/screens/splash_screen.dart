import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Loading duration
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward().then((_) {
      final isLoggedIn =
          context.read<MatrixProvider>().isLoggedIn;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              isLoggedIn ? const HomeScreen() : const LoginScreen(),
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
          // Background Image
          Image.asset(
            'assets/images/splash_bg.png',
            fit: BoxFit.cover,
          ),
          
          // Subtle dark overlay to ensure the thin white line is visible
          Container(
            color: Colors.black.withOpacity(0.2),
          ),
          
          // Progress Bar and Text at the bottom
          Positioned(
            bottom: 40,
            left: 50,
            right: 50,
            child: AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                final percent = (_progressAnimation.value * 100).toInt();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App Logo / Name
                    Text(
                      'XMO',
                      style: GoogleFonts.cormorantGaramond(
                        color: Colors.white,
                        fontSize: 32,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 3.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Thin progress line container
                    SizedBox(
                      height: 1.5,
                      child: Stack(
                        children: [
                          // Background line (faded)
                          Container(
                            width: double.infinity,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          // Foreground line (progress)
                          FractionallySizedBox(
                            widthFactor: _progressAnimation.value,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Percentage text
                    Text(
                      '$percent%',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
