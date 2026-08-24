import 'package:flutter/material.dart';
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
    labelStyle: const TextStyle(color: kLightGrey),
    enabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: kDarkGrey),
    ),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: kLimeGreen),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBlack,
    appBar: AppBar(
      title: const Text('Recovery email'),
      backgroundColor: kBlack,
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'A recovery email can reset your password and delete your account. '
          'You must confirm both the existing and new email addresses.',
          style: TextStyle(color: kLightGrey, height: 1.4),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: const TextStyle(color: kWhite),
          decoration: _decoration('New recovery email'),
          enabled: _transactionId == null && !_busy,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          style: const TextStyle(color: kWhite),
          decoration: _decoration(
            'Current password (required for legacy accounts)',
          ),
          enabled: _transactionId == null && !_busy,
        ),
        if (_transactionId == null) ...[
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _start,
            child: Text(_busy ? 'Sending…' : 'Send confirmation codes'),
          ),
        ] else ...[
          const SizedBox(height: 18),
          TextField(
            controller: _currentCode,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: kWhite),
            decoration: _decoration('Code sent to existing email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newCode,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: kWhite),
            decoration: _decoration('Code sent to new email'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _confirm,
            child: Text(_busy ? 'Verifying…' : 'Confirm recovery email'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
      ],
    ),
  );
}
