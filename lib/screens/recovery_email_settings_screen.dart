import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../services/otp_service.dart';
import '../theme.dart';

class RecoveryEmailSettingsScreen extends StatefulWidget {
  const RecoveryEmailSettingsScreen({super.key});

  @override
  State<RecoveryEmailSettingsScreen> createState() =>
      _RecoveryEmailSettingsScreenState();
}

class _RecoveryEmailSettingsScreenState
    extends State<RecoveryEmailSettingsScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _currentCode = TextEditingController();
  final _newCode = TextEditingController();
  String? _transactionId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _currentCode.dispose();
    _newCode.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter a recovery email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final token = context.read<MatrixProvider>().service.accessToken ?? '';
    final result = await OtpService().startRecoveryEmailChange(
      accessToken: token,
      email: email,
      currentPassword: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _transactionId = result.transactionId;
      _error = result.success
          ? null
          : (result.error ?? 'Could not start recovery email setup.');
    });
    if (result.success && result.transactionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That recovery email is already active.')),
      );
    }
  }

  Future<void> _confirm() async {
    final transactionId = _transactionId;
    if (transactionId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final token = context.read<MatrixProvider>().service.accessToken ?? '';
    final error = await OtpService().confirmRecoveryEmailChange(
      accessToken: token,
      transactionId: transactionId,
      currentEmailCode: _currentCode.text.trim(),
      newEmailCode: _newCode.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery email updated successfully.')),
      );
      Navigator.pop(context);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.inter(
      color: kLightGrey,
      fontSize: 13,
      fontWeight: FontWeight.w400,
    ),
    floatingLabelStyle: GoogleFonts.inter(
      color: kLightGrey,
      fontSize: 13,
      fontWeight: FontWeight.w400,
    ),
    contentPadding: const EdgeInsets.only(top: 10, bottom: 13),
    enabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: kDarkGrey),
    ),
    disabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: kDarkGrey),
    ),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: kWhite),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBlack,
    appBar: AppBar(
      title: Text(
        'Recovery email',
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor: kBlack,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      children: [
        Text(
          'A recovery email can reset your password and delete your account. '
          'You must confirm both the existing and new email addresses.',
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 26),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: GoogleFonts.inter(color: kWhite, fontSize: 15),
          decoration: _decoration('New recovery email'),
          enabled: _transactionId == null && !_busy,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _password,
          obscureText: true,
          style: GoogleFonts.inter(color: kWhite, fontSize: 15),
          decoration: _decoration(
            'Current password (required for legacy accounts)',
          ),
          enabled: _transactionId == null && !_busy,
        ),
        if (_transactionId == null) ...[
          const SizedBox(height: 28),
          _primaryButton(
            onPressed: _busy ? null : _start,
            label: _busy ? 'Sending…' : 'Send confirmation codes',
          ),
        ] else ...[
          const SizedBox(height: 28),
          TextField(
            controller: _currentCode,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(color: kWhite, fontSize: 15),
            decoration: _decoration('Code sent to existing email'),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _newCode,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(color: kWhite, fontSize: 15),
            decoration: _decoration('Code sent to new email'),
          ),
          const SizedBox(height: 28),
          _primaryButton(
            onPressed: _busy ? null : _confirm,
            label: _busy ? 'Verifying…' : 'Confirm recovery email',
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 24),
          Text(
            _error!,
            style: GoogleFonts.inter(
              color: const Color(0xFFFF646E),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _primaryButton({
    required VoidCallback? onPressed,
    required String label,
  }) {
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kWhite,
          foregroundColor: kBlack,
          disabledBackgroundColor: const Color(0xFF252525),
          disabledForegroundColor: kLightGrey,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
