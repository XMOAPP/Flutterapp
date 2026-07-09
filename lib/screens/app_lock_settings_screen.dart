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
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            children: [
              _settingsCard(
                children: [
                  _switchRow(
                    icon: Icons.lock_outline,
                    title: 'Lock XMO',
                    subtitle:
                        'Require a PIN when XMO is opened after inactivity.',
                    value: _service.enabled,
                    onChanged: _working ? null : _toggleLock,
                  ),
                  if (_service.enabled) ...[
                    _cardDivider(),
                    _switchRow(
                      icon: Icons.fingerprint,
                      title: 'Unlock with biometrics',
                      subtitle: _biometricsAvailable
                          ? 'Use fingerprint or face authentication.'
                          : 'Biometric authentication is unavailable.',
                      value: _service.biometricEnabled,
                      onChanged: !_biometricsAvailable || _working
                          ? null
                          : (value) =>
                              _run(() => _service.setBiometricEnabled(value)),
                    ),
                  ],
                ],
              ),
              if (_service.enabled) ...[
                const SizedBox(height: 16),
                _settingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'AUTO-LOCK',
                          style: GoogleFonts.inter(
                            color: kLightGrey,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                    ..._timeoutEntries().expand(
                      (entry) sync* {
                        yield _timeoutOption(
                          value: entry.key,
                          label: entry.value,
                        );
                        if (entry.key != 1800) yield _cardDivider();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: SizedBox(
                    height: 42,
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kWhite,
                        foregroundColor: kBlack,
                        disabledBackgroundColor: kWhite.withValues(alpha: 0.45),
                        disabledForegroundColor: kBlack.withValues(alpha: 0.45),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(21),
                        ),
                      ),
                      onPressed: _working
                          ? null
                          : () {
                              _service.lockNow();
                              Navigator.pop(context);
                            },
                      child: Text(
                        'Lock now',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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

  Iterable<MapEntry<int, String>> _timeoutEntries() => const {
        0: 'Immediately',
        30: 'After 30 seconds',
        60: 'After 1 minute',
        300: 'After 5 minutes',
        1800: 'After 30 minutes',
      }.entries;

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

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11171D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _cardDivider() {
    return const Divider(
      color: Color(0xFF242B33),
      height: 1,
      indent: 72,
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF252B33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: kWhite, size: 21),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(title),
                const SizedBox(height: 4),
                _subtitle(subtitle),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeThumbColor: kLimeGreen,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _timeoutOption({
    required int value,
    required String label,
  }) {
    final selected = _service.timeoutSeconds == value;
    return InkWell(
      onTap: _working ? null : () => _run(() => _service.setTimeout(value)),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            _iconBox(value == 0 ? Icons.timer_outlined : Icons.schedule),
            const SizedBox(width: 14),
            Expanded(child: _title(label)),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? kLimeGreen : kLightGrey,
              size: 23,
            ),
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
  bool _showPin = false;
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
      obscureText: !_showPin,
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
      cursorColor: kWhite,
      style: GoogleFonts.inter(color: kWhite, fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 15),
        filled: true,
        fillColor: const Color(0xFF2C2C2E),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _showPin = !_showPin),
          icon: Icon(
            _showPin
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: kLightGrey,
            size: 20,
          ),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              BorderSide(color: kWhite.withValues(alpha: 0.45), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 62, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(28, 26, 28, 12),
      contentPadding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
      actionsPadding: const EdgeInsets.fromLTRB(18, 0, 22, 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      title: Text(
        widget.title,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
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
          style: TextButton.styleFrom(foregroundColor: kWhite),
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(fontWeight: FontWeight.w500),
          ),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(foregroundColor: kWhite),
          child: Text(
            'Continue',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
