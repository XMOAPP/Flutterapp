import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../services/app_lock_service.dart';
import '../theme.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  String? _configuredUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final matrixProvider = context.watch<MatrixProvider>();
    final userId = matrixProvider.state == MatrixAuthState.loggedIn
        ? matrixProvider.userId
        : null;
    if (_configuredUserId == userId) return;
    _configuredUserId = userId;
    unawaited(AppLockService.instance.configureForUser(userId));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppLockService.instance,
      builder: (context, _) {
        final lock = AppLockService.instance;
        final isProtectedSession = _configuredUserId?.isNotEmpty ?? false;

        // Never render authenticated content before secure lock settings load.
        // This also keeps protected routes out of the tree while locked.
        if (isProtectedSession && !lock.initialized) {
          return const ColoredBox(color: kBlack);
        }
        if (lock.initialized && lock.locked) {
          return const _AppLockScreen();
        }
        return widget.child;
      },
    );
  }
}

class _AppLockScreen extends StatefulWidget {
  const _AppLockScreen();

  @override
  State<_AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<_AppLockScreen>
    with TickerProviderStateMixin {
  String _pin = '';
  bool _working = false;
  bool _showLastDigit = false;
  String? _error;
  Timer? _maskTimer;
  Timer? _lockoutTimer;
  late final AnimationController _emblemController;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _emblemController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    if (AppLockService.instance.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useBiometric());
    }
  }

  @override
  void dispose() {
    _maskTimer?.cancel();
    _lockoutTimer?.cancel();
    _emblemController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  bool get _blocked {
    final until = AppLockService.instance.blockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  int get _remainingLockoutSeconds {
    final until = AppLockService.instance.blockedUntil;
    if (until == null) return 0;
    final milliseconds = until.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds / 1000).ceil();
  }

  void _enterDigit(String digit) {
    if (_working || _blocked) return;
    final expectedLength = AppLockService.instance.pinLength;
    if (_pin.length >= (expectedLength ?? 8)) return;

    HapticFeedback.selectionClick();
    _maskTimer?.cancel();
    setState(() {
      _pin += digit;
      _showLastDigit = true;
      _error = null;
    });
    _maskTimer = Timer(const Duration(milliseconds: 480), () {
      if (mounted) setState(() => _showLastDigit = false);
    });

    if (expectedLength != null && _pin.length == expectedLength) {
      unawaited(_verifyPin());
    }
  }

  void _removeDigit() {
    if (_working || _blocked || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    _maskTimer?.cancel();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _showLastDigit = false;
      _error = null;
    });
  }

  void _startLockoutTicker() {
    _lockoutTimer?.cancel();
    if (!_blocked) return;
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_blocked) {
        timer.cancel();
        setState(() => _error = null);
        return;
      }
      setState(() {});
    });
  }

  Future<void> _verifyPin() async {
    if (_working || _blocked) return;
    if (_pin.length < 4) {
      setState(() => _error = 'Enter at least 4 digits');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final ok = await AppLockService.instance.verifyPin(_pin);
    if (!mounted) return;
    if (ok) {
      setState(() => _working = false);
      return;
    }
    final blockedUntil = AppLockService.instance.blockedUntil;
    HapticFeedback.mediumImpact();
    setState(() {
      _working = false;
      _pin = '';
      _showLastDigit = false;
      _error = blockedUntil == null
          ? 'Incorrect PIN'
          : 'Try again in $_remainingLockoutSeconds seconds';
    });
    _shakeController.forward(from: 0);
    _startLockoutTicker();
  }

  Future<void> _useBiometric() async {
    if (_working) return;
    setState(() => _working = true);
    final ok = await AppLockService.instance.authenticateBiometric();
    if (!mounted || ok) return;
    setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasBiometrics = AppLockService.instance.biometricEnabled;
    return Material(
      color: kBlack,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 700;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  compact ? 12 : 24,
                  24,
                  compact ? 12 : 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _lockEmblem(compact: compact),
                      SizedBox(height: compact ? 12 : 16),
                      Text(
                        'Enter your PIN',
                        style: GoogleFonts.inter(
                          color: kLightGrey,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: compact ? 14 : 20),
                      _pinIndicator(),
                      SizedBox(height: compact ? 8 : 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: SizedBox(
                          key: ValueKey(_statusText),
                          height: 20,
                          child: Text(
                            _statusText,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: _error == null
                                  ? kLightGrey
                                  : Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 14),
                      _numberPad(compact: compact),
                      if (hasBiometrics) ...[
                        SizedBox(height: compact ? 8 : 14),
                        _biometricControl(),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String get _statusText {
    if (_working) return 'Checking PIN...';
    if (_blocked) return 'Try again in $_remainingLockoutSeconds seconds';
    if (_error != null) return _error!;
    if (AppLockService.instance.pinLength == null && _pin.length >= 4) {
      return 'Tap the check button to unlock';
    }
    return '';
  }

  Widget _lockEmblem({required bool compact}) {
    final size = compact ? 28.0 : 32.0;
    return AnimatedBuilder(
      animation: _emblemController,
      builder: (context, child) {
        final scale = 0.96 + (_emblemController.value * 0.04);
        return Transform.scale(scale: scale, child: child);
      },
      child: Icon(Icons.lock_rounded, color: kWhite, size: size),
    );
  }

  Widget _pinIndicator() {
    final expectedLength = AppLockService.instance.pinLength;
    final slotCount = expectedLength ?? (_pin.length > 4 ? _pin.length : 4);
    final animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = animation.value;
        final offset = progress == 0
            ? 0.0
            : (1 - progress) *
                8 *
                (progress < 0.25
                    ? 1
                    : progress < 0.5
                        ? -1
                        : progress < 0.75
                            ? 1
                            : -1);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(slotCount, (index) {
          final entered = index < _pin.length;
          final reveal = entered && index == _pin.length - 1 && _showLastDigit;
          return Container(
            width: 31,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Text(
                entered ? (reveal ? _pin[index] : '•') : '○',
                key: ValueKey('$entered-$reveal-${entered ? _pin[index] : ''}'),
                style: GoogleFonts.inter(
                  color: entered ? kWhite : kLightGrey,
                  fontSize: reveal ? 23 : 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _numberPad({required bool compact}) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    final buttonSize = compact ? 54.0 : 60.0;
    final rowGap = compact ? 7.0 : 9.0;
    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row
                .map(
                  (digit) => _PinKey(
                    size: buttonSize,
                    label: digit,
                    onPressed: () => _enterDigit(digit),
                    enabled: !_working && !_blocked,
                  ),
                )
                .toList(),
          ),
          SizedBox(height: rowGap),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: IconButton(
                onPressed:
                    _working || _blocked || _pin.isEmpty ? null : _removeDigit,
                icon: Icon(
                  Icons.backspace_rounded,
                  color: _pin.isEmpty
                      ? kLightGrey.withValues(alpha: 0.35)
                      : kWhite,
                  size: 23,
                ),
              ),
            ),
            _PinKey(
              size: buttonSize,
              label: '0',
              onPressed: () => _enterDigit('0'),
              enabled: !_working && !_blocked,
            ),
            SizedBox(
              width: buttonSize,
              height: buttonSize,
              child:
                  AppLockService.instance.pinLength == null && _pin.length >= 4
                      ? IconButton(
                          onPressed: _working || _blocked ? null : _verifyPin,
                          icon: const Icon(
                            Icons.check_rounded,
                            color: kWhite,
                            size: 26,
                          ),
                        )
                      : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _biometricControl() {
    return Semantics(
      button: true,
      label: 'Unlock with biometrics',
      child: InkResponse(
        onTap: _working || _blocked ? null : _useBiometric,
        radius: 34,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fingerprint,
                color: _working || _blocked ? kLightGrey : kWhite,
                size: 30,
              ),
              const SizedBox(height: 3),
              Text(
                'Biometrics',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinKey extends StatefulWidget {
  const _PinKey({
    required this.size,
    required this.label,
    required this.onPressed,
    required this.enabled,
  });

  final double size;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel:
            widget.enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  _pressed ? const Color(0xFF4A4D50) : const Color(0xFF303438),
            ),
            child: Text(
              widget.label,
              style: GoogleFonts.inter(
                color: widget.enabled ? kWhite : kWhite.withValues(alpha: 0.35),
                fontSize: 29,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
