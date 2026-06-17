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
        return Stack(
          children: [
            widget.child,
            if (lock.initialized && lock.locked)
              const Positioned.fill(child: _AppLockScreen()),
          ],
        );
      },
    );
  }
}

class _AppLockScreen extends StatefulWidget {
  const _AppLockScreen();

  @override
  State<_AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<_AppLockScreen> {
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();
  bool _working = false;
  bool _pinVisible = false;
  int _pinInputRevision = 0;
  String _lastCleanPin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (AppLockService.instance.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useBiometric());
    }
  }

  @override
  void dispose() {
    _pinFocusNode.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _resetPinInputConnection({bool keepFocus = true}) {
    _pinController.value = TextEditingValue.empty;
    _lastCleanPin = '';
    setState(() => _pinInputRevision++);
    if (!keepFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pinFocusNode.requestFocus();
    });
  }

  void _handlePinChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      _lastCleanPin = '';
      return;
    }

    final previous = _lastCleanPin;
    var next = digits;

    // Some Android keyboards can resend stale composing text after the user
    // deletes the field. If the new value is the old PIN plus one fresh digit,
    // keep only that fresh digit instead of restoring the deleted PIN.
    if (previous.isEmpty && digits.length > 1) {
      next = digits.substring(digits.length - 1);
    }

    if (next.length > 8) {
      next = next.substring(0, 8);
    }

    _lastCleanPin = next;
    if (next == value) return;

    _pinController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _verifyPin() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final ok = await AppLockService.instance.verifyPin(_pinController.text);
    if (!mounted) return;
    if (ok) {
      setState(() => _working = false);
      return;
    }
    final blockedUntil = AppLockService.instance.blockedUntil;
    setState(() {
      _working = false;
      _error = blockedUntil == null
          ? 'Incorrect PIN'
          : 'Too many attempts. Try again in 30 seconds.';
    });
    _resetPinInputConnection();
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
    return Material(
      color: kBlack,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 38),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, color: kWhite, size: 44),
                const SizedBox(height: 22),
                Text(
                  'XMO is locked',
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  key: ValueKey('app-lock-pin-$_pinInputRevision'),
                  controller: _pinController,
                  focusNode: _pinFocusNode,
                  obscureText: !_pinVisible,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: const <String>[],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  onChanged: _handlePinChanged,
                  onSubmitted: (_) => _verifyPin(),
                  maxLength: 8,
                  style: GoogleFonts.inter(color: kWhite, fontSize: 18),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Enter PIN',
                    hintStyle: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 18,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1C1C1D),
                    errorText: _error,
                    suffixIcon: Semantics(
                      label: _pinVisible ? 'Hide PIN' : 'Show PIN',
                      button: true,
                      child: IconButton(
                        onPressed: () {
                          setState(() => _pinVisible = !_pinVisible);
                        },
                        icon: Icon(
                          _pinVisible ? Icons.visibility_off : Icons.visibility,
                          color: kLightGrey,
                        ),
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 386),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kWhite,
                        foregroundColor: kBlack,
                        disabledBackgroundColor: kWhite.withValues(alpha: 0.55),
                        disabledForegroundColor: kBlack.withValues(alpha: 0.55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: _working ? null : _verifyPin,
                      child: Text(
                        _working ? 'Unlocking...' : 'Unlock',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (AppLockService.instance.biometricEnabled) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Use biometrics',
                    button: true,
                    child: IconButton(
                      onPressed: _working ? null : _useBiometric,
                      icon: const Icon(
                        Icons.fingerprint,
                        color: kWhite,
                        size: 38,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
