import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xmo/utils/user_facing_error.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';

import '../services/e2ee_service.dart';
import '../services/matrix_device_verification_service.dart';
import '../services/matrix_service.dart';
import '../theme.dart';

class DeviceVerificationScreen extends StatefulWidget {
  const DeviceVerificationScreen({
    super.key,
    required this.verification,
    required this.matrixService,
  });

  final KeyVerification verification;
  final MatrixService matrixService;

  @override
  State<DeviceVerificationScreen> createState() =>
      _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends State<DeviceVerificationScreen> {
  late final MatrixDeviceVerificationService _service;
  void Function()? _previousOnUpdate;
  bool _working = false;
  bool _recoveryRequested = false;
  E2eeStatus? _recoveryStatus;
  String? _error;

  KeyVerification get _verification => widget.verification;

  @override
  void initState() {
    super.initState();
    _service = MatrixDeviceVerificationService(widget.matrixService);
    _previousOnUpdate = _verification.onUpdate;
    _verification.onUpdate = _onVerificationUpdate;
    if (_verification.state == KeyVerificationState.done) {
      unawaited(_requestRecoverySecrets());
    }
  }

  @override
  void dispose() {
    _verification.onUpdate = _previousOnUpdate;
    super.dispose();
  }

  void _onVerificationUpdate() {
    _previousOnUpdate?.call();
    if (!mounted) return;
    setState(() {});
    if (_verification.state == KeyVerificationState.done) {
      unawaited(_requestRecoverySecrets());
    }
  }

  Future<void> _requestRecoverySecrets() async {
    if (_recoveryRequested) return;
    _recoveryRequested = true;
    try {
      await _verification.maybeRequestSSSSSecrets();
      final status = await _service.requestRecoverySecrets();
      if (mounted) setState(() => _recoveryStatus = status);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Device verified, but recovery keys could not be requested yet.';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingError(
            error,
            fallback: 'Device verification failed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _verification.state;
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(
          'Verify device',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          children: [
            _statusIcon(state),
            const SizedBox(height: 20),
            Text(
              _title(state),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _message(state),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
            ),
            if (state == KeyVerificationState.askSas) ...[
              const SizedBox(height: 24),
              _sasPanel(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 18),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 26),
            ..._actions(state),
            if (_working) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator(color: kLimeGreen)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(KeyVerificationState state) {
    final done = state == KeyVerificationState.done;
    final failed = state == KeyVerificationState.error;
    return Center(
      child: Container(
        width: 58,
        height: 58,
        decoration: const BoxDecoration(
          color: Color(0xFF1C232B),
          shape: BoxShape.circle,
        ),
        child: Icon(
          done
              ? Icons.verified
              : failed
              ? Icons.error_outline
              : Icons.phonelink_lock,
          color: done
              ? kLimeGreen
              : failed
              ? Colors.redAccent
              : kWhite,
          size: 30,
        ),
      ),
    );
  }

  String _title(KeyVerificationState state) {
    switch (state) {
      case KeyVerificationState.askAccept:
        return 'Verification request';
      case KeyVerificationState.askChoice:
        return 'Choose verification';
      case KeyVerificationState.askSas:
        return 'Compare security codes';
      case KeyVerificationState.askSSSS:
        return 'Verify with another device';
      case KeyVerificationState.done:
        return 'Device verified';
      case KeyVerificationState.error:
        return 'Verification cancelled';
      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.waitingSas:
      case KeyVerificationState.showQRSuccess:
      case KeyVerificationState.confirmQRScan:
        return 'Waiting for the other device';
    }
  }

  String _message(KeyVerificationState state) {
    switch (state) {
      case KeyVerificationState.askAccept:
        return 'Confirm this request only if you started it on your other XMO device.';
      case KeyVerificationState.askChoice:
        return 'Use emoji and numbers to confirm both devices show the same code.';
      case KeyVerificationState.askSas:
        return 'The emoji and numbers must match exactly on both devices.';
      case KeyVerificationState.askSSSS:
        return 'Continue to verify this session with an existing trusted device.';
      case KeyVerificationState.done:
        final status = _recoveryStatus;
        if (status?.crossSigningCached == true &&
            status?.keyBackupCached == true) {
          return 'Trust is established and recovery keys are available on this device.';
        }
        return 'Trust is established. XMO requested recovery secrets. Older messages become readable as keys arrive or after recovery is unlocked.';
      case KeyVerificationState.error:
        return _verification.canceledReason ??
            _verification.canceledCode ??
            'The request did not complete.';
      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.waitingSas:
      case KeyVerificationState.showQRSuccess:
      case KeyVerificationState.confirmQRScan:
        return 'Keep both devices open until verification finishes.';
    }
  }

  Widget _sasPanel() {
    final emojis = _verification.sasEmojis;
    final numbers = _verification.sasNumbers;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11171D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (emojis.isNotEmpty)
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: emojis
                  .map(
                    (item) => SizedBox(
                      width: 58,
                      child: Column(
                        children: [
                          Text(
                            item.emoji,
                            style: const TextStyle(fontSize: 30),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.name,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: kLightGrey,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (numbers.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              numbers.join('   '),
              style: GoogleFonts.robotoMono(
                color: kWhite,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(KeyVerificationState state) {
    switch (state) {
      case KeyVerificationState.askAccept:
        return [
          _button(
            'Accept request',
            () => _run(_verification.acceptVerification),
          ),
          const SizedBox(height: 10),
          _button(
            'Reject',
            () => _run(_verification.rejectVerification),
            outlined: true,
          ),
        ];
      case KeyVerificationState.askChoice:
        final supportsSas = _verification.possibleMethods.contains(
          EventTypes.Sas,
        );
        return [
          _button(
            'Compare emoji and numbers',
            supportsSas
                ? () => _run(
                    () => _verification.continueVerification(EventTypes.Sas),
                  )
                : null,
          ),
        ];
      case KeyVerificationState.askSas:
        return [
          _button('They match', () => _run(_verification.acceptSas)),
          const SizedBox(height: 10),
          _button(
            'They do not match',
            () => _run(_verification.rejectSas),
            outlined: true,
          ),
        ];
      case KeyVerificationState.askSSSS:
        return [
          _button(
            'Continue with device verification',
            () => _run(() => _verification.openSSSS(skip: true)),
          ),
        ];
      case KeyVerificationState.done:
        return [_button('Done', () => Navigator.pop(context, true))];
      case KeyVerificationState.error:
        return [_button('Close', () => Navigator.pop(context, false))];
      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.waitingSas:
      case KeyVerificationState.showQRSuccess:
      case KeyVerificationState.confirmQRScan:
        return [
          _button(
            'Cancel verification',
            () => _run(() => _verification.cancel('m.user')),
            outlined: true,
          ),
        ];
    }
  }

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    bool outlined = false,
  }) {
    final style = outlined
        ? OutlinedButton.styleFrom(
            foregroundColor: kWhite,
            side: const BorderSide(color: Color(0xFF53606C)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: kWhite,
            foregroundColor: kBlack,
            disabledBackgroundColor: const Color(0xFF20262D),
            disabledForegroundColor: kLightGrey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          );
    final child = Text(
      label,
      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
    );
    return SizedBox(
      height: 48,
      child: outlined
          ? OutlinedButton(style: style, onPressed: onPressed, child: child)
          : ElevatedButton(style: style, onPressed: onPressed, child: child),
    );
  }
}
