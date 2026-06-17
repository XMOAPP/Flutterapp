import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_lock_service.dart';
import '../theme.dart';

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  final AppLockService _service = AppLockService.instance;
  bool _working = false;
  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricStatus();
  }

  Future<void> _loadBiometricStatus() async {
    final available = await _service.canUseBiometrics();
    if (mounted) setState(() => _biometricsAvailable = available);
  }

  Future<void> _toggleLock(bool enabled) async {
    if (_working) return;
    if (!enabled) {
      final pin = await _askForPin(
        title: 'Disable app lock',
        confirm: false,
      );
      if (pin == null) return;
      await _run(() => _service.disable(pin));
      return;
    }

    final pin = await _askForPin(
      title: 'Create app lock PIN',
      confirm: true,
    );
    if (pin == null) return;
    await _run(
      () => _service.enable(
        pin: pin,
        useBiometrics: false,
        timeoutSeconds: _service.timeoutSeconds,
      ),
    );
  }

  Future<String?> _askForPin({
    required String title,
    required bool confirm,
  }) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AppLockPinDialog(title: title, confirm: confirm),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _messageFor(Object error) {
    final message = error.toString();
    return message
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: kBlack,
          appBar: AppBar(
            title: Text(
              'App Lock',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: _title('Lock XMO'),
                subtitle: _subtitle(
                  'Require a PIN when XMO is opened after inactivity.',
                ),
                value: _service.enabled,
                activeThumbColor: kLimeGreen,
                onChanged: _working ? null : _toggleLock,
              ),
              if (_service.enabled) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: _title('Unlock with biometrics'),
                  subtitle: _subtitle(
                    _biometricsAvailable
                        ? 'Use fingerprint or face authentication.'
                        : 'Biometric authentication is unavailable.',
                  ),
                  value: _service.biometricEnabled,
                  activeThumbColor: kLimeGreen,
                  onChanged: !_biometricsAvailable || _working
                      ? null
                      : (value) =>
                          _run(() => _service.setBiometricEnabled(value)),
                ),
                const SizedBox(height: 16),
                Text(
                  'AUTO-LOCK',
                  style: GoogleFonts.inter(
                    color: kLightGrey,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ...const {
                  0: 'Immediately',
                  30: 'After 30 seconds',
                  60: 'After 1 minute',
                  300: 'After 5 minutes',
                  1800: 'After 30 minutes',
                }.entries.map(
                      (entry) => _timeoutOption(
                        value: entry.key,
                        label: entry.value,
                      ),
                    ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _working
                        ? null
                        : () {
                            _service.lockNow();
                            Navigator.pop(context);
                          },
                    child: const Text('Lock now'),
                  ),
                ),
              ],
              if (_working) ...[
                const SizedBox(height: 20),
                const Center(
                  child: CircularProgressIndicator(color: kLimeGreen),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Text _title(String text) => Text(
        text,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );

  Text _subtitle(String text) => Text(
        text,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
      );

  Widget _timeoutOption({
    required int value,
    required String label,
  }) {
    final selected = _service.timeoutSeconds == value;
    return InkWell(
      onTap: _working ? null : () => _run(() => _service.setTimeout(value)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? kLimeGreen : kLightGrey,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(child: _title(label)),
          ],
        ),
      ),
    );
  }
}

class _AppLockPinDialog extends StatefulWidget {
  final String title;
  final bool confirm;

  const _AppLockPinDialog({
    required this.title,
    required this.confirm,
  });

  @override
  State<_AppLockPinDialog> createState() => _AppLockPinDialogState();
}

class _AppLockPinDialogState extends State<_AppLockPinDialog> {
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context, rootNavigator: true).pop(value);
  }

  void _submit() {
    final value = _pin.text.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(value)) {
      setState(() => _error = 'Use a 4 to 8 digit PIN');
      return;
    }
    if (widget.confirm && value != _confirmation.text.trim()) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    _close(value);
  }

  Widget _pinField(
    TextEditingController controller,
    String hint, {
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      textInputAction: widget.confirm && controller == _pin
          ? TextInputAction.next
          : TextInputAction.done,
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: const <String>[],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      style: GoogleFonts.inter(color: kWhite),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: kLightGrey),
        filled: true,
        fillColor: const Color(0xFF2C2C2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      onSubmitted: (_) {
        if (!widget.confirm || controller == _confirmation) {
          _submit();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kDarkerGrey,
      title: Text(
        widget.title,
        style: GoogleFonts.inter(color: kWhite, fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pinField(_pin, 'PIN', autofocus: true),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            _pinField(_confirmation, 'Confirm PIN'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
