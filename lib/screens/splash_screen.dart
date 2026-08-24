import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import 'auth_choice_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  MatrixProvider? _provider;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialScreen());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<MatrixProvider>();
    if (_provider == provider) return;
    _provider?.removeListener(_openInitialScreen);
    _provider = provider..addListener(_openInitialScreen);
  }

  @override
  void dispose() {
    _provider?.removeListener(_openInitialScreen);
    super.dispose();
  }

  void _openInitialScreen() {
    if (!mounted || _navigated) return;

    final provider = context.read<MatrixProvider>();
    if (provider.state == MatrixAuthState.uninitialized) return;

    _navigated = true;
    final destination = provider.isLoggedIn
        ? const HomeScreen()
        : const AuthChoiceScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => destination,
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
      body: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, 24),
            child: const SizedBox.square(
              dimension: 200,
              child: Image(
                image: AssetImage(
                  'assets/images/cropped_circle_image(1)(1).png',
                ),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
