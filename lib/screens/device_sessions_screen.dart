import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../services/device_session_service.dart';
import '../theme.dart';

class DeviceSessionsScreen extends StatefulWidget {
  const DeviceSessionsScreen({super.key});

  @override
  State<DeviceSessionsScreen> createState() => _DeviceSessionsScreenState();
}

class _DeviceSessionsScreenState extends State<DeviceSessionsScreen> {
  late final DeviceSessionService _service;
  List<DeviceSession> _sessions = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = DeviceSessionService(context.read<MatrixProvider>().service);
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await _service.load();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load devices: $error';
      });
    }
  }

  Future<void> _rename(DeviceSession session) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDeviceDialog(
        initialName: session.device.displayName ?? '',
      ),
    );
    if (name == null || name.isEmpty) return;
    await _run(() => _service.rename(session.device.deviceId, name));
  }

  Future<void> _signOut(DeviceSession session) async {
    final confirmed = await _confirm(
      'Sign out this device?',
      'The Matrix session on ${_deviceName(session)} will be invalidated.',
    );
    if (!confirmed) return;

    try {
      await _run(() => _service.delete(session.device.deviceId));
    } on DeviceReauthenticationRequired catch (challenge) {
      final password = await _askForPassword();
      if (password == null) return;
      await _run(
        () => _service.delete(
          session.device.deviceId,
          password: password,
          session: challenge.session,
        ),
      );
    }
  }

  Future<void> _signOutAllOthers() async {
    final confirmed = await _confirm(
      'Sign out all other devices?',
      'Every Matrix session except this device will be invalidated.',
    );
    if (!confirmed) return;

    try {
      await _run(_service.deleteAllOther);
    } on DeviceReauthenticationRequired catch (challenge) {
      final password = await _askForPassword();
      if (password == null) return;
      await _run(
        () => _service.deleteAllOther(
          password: password,
          session: challenge.session,
        ),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
      await _load();
    } on DeviceReauthenticationRequired {
      rethrow;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device action failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: kDarkerGrey,
            title: Text(title, style: GoogleFonts.inter(color: kWhite)),
            content: Text(
              message,
              style: GoogleFonts.inter(color: kLightGrey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Sign out',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _askForPassword() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PasswordDialog(),
    );
  }

  String _deviceName(DeviceSession session) {
    final name = session.device.displayName?.trim();
    return name?.isNotEmpty == true ? name! : 'Unknown device';
  }

  String _lastSeen(DeviceSession session) {
    final timestamp = session.device.lastSeenTs;
    if (timestamp == null) return 'Last seen unavailable';
    final value = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) return 'Active now';
    if (difference.inHours < 1) {
      return 'Last seen ${difference.inMinutes}m ago';
    }
    if (difference.inDays < 1) {
      return 'Last seen ${difference.inHours}h ago';
    }
    return 'Last seen ${difference.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(
          'Devices and Sessions',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: kLimeGreen),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(color: kLightGrey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                  children: [
                    Text(
                      'These are the Matrix sessions currently signed in to your account.',
                      style: GoogleFonts.inter(
                        color: kLightGrey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._sessions.map(_deviceTile),
                    if (_sessions.any((session) => !session.isCurrent)) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C2C2E),
                            foregroundColor: Colors.redAccent,
                          ),
                          onPressed: _working ? null : _signOutAllOthers,
                          child: const Text('Sign out all other devices'),
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
  }

  Widget _deviceTile(DeviceSession session) {
    final subtitle = [
      session.isCurrent
          ? 'This device'
          : session.isVerified
              ? 'Verified session'
              : 'Unverified session',
      _lastSeen(session),
      if (session.device.lastSeenIp?.isNotEmpty == true)
        session.device.lastSeenIp!,
    ].join(' - ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        session.isCurrent ? Icons.smartphone : Icons.devices,
        color:
            session.isVerified || session.isCurrent ? kLimeGreen : kLightGrey,
      ),
      title: Text(
        _deviceName(session),
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '$subtitle\n${session.device.deviceId}',
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        color: kDarkerGrey,
        iconColor: kWhite,
        onSelected: (value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (value == 'rename') _rename(session);
            if (value == 'sign_out') _signOut(session);
          });
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          if (!session.isCurrent)
            const PopupMenuItem(
              value: 'sign_out',
              child: Text(
                'Sign out',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
        ],
      ),
    );
  }
}

class _RenameDeviceDialog extends StatefulWidget {
  final String initialName;

  const _RenameDeviceDialog({required this.initialName});

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context, rootNavigator: true).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kDarkerGrey,
      title: Text(
        'Rename device',
        style: GoogleFonts.inter(color: kWhite, fontSize: 18),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: GoogleFonts.inter(color: kWhite),
        decoration: const InputDecoration(
          hintText: 'Device name',
          filled: true,
          fillColor: Color(0xFF2C2C2E),
        ),
        onSubmitted: (_) => _close(_controller.text.trim()),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _close(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context, rootNavigator: true).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kDarkerGrey,
      title: Text(
        'Confirm password',
        style: GoogleFonts.inter(color: kWhite),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        style: GoogleFonts.inter(color: kWhite),
        decoration: const InputDecoration(
          hintText: 'Matrix account password',
          filled: true,
          fillColor: Color(0xFF2C2C2E),
        ),
        onSubmitted: (_) => _close(_controller.text),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _close(_controller.text),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
