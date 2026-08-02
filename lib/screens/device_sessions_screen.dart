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
      'The XMO session on ${_deviceName(session)} will be signed out.',
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
      'Every XMO session except this device will be signed out.',
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
    if (name?.isNotEmpty == true) return name!;
    if (session.isCurrent) return 'This device';
    final id = session.device.deviceId;
    if (id.length <= 6) return 'Device $id';
    return 'Device ${id.substring(0, 6)}';
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
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                  children: [
                    Text(
                      'These are the devices currently signed in to your XMO account.',
                      style: GoogleFonts.inter(
                        color: kLightGrey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _settingsCard(
                      children: [
                        for (var i = 0; i < _sessions.length; i++) ...[
                          _deviceTile(_sessions[i]),
                          if (i != _sessions.length - 1) _divider(),
                        ],
                      ],
                    ),
                    if (_sessions.any((session) => !session.isCurrent)) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: SizedBox(
                          width: 270,
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kWhite,
                              foregroundColor: kBlack,
                              disabledBackgroundColor: const Color(0xFF2C2C2E),
                              disabledForegroundColor: kLightGrey,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                              textStyle: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: _working ? null : _signOutAllOthers,
                            child: const Text('Sign out all other devices'),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _deviceIcon(session.isCurrent ? Icons.smartphone : Icons.devices),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _deviceName(session),
                        style: GoogleFonts.inter(
                          color: kWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (session.isCurrent) ...[
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: kLimeGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Active now',
                            style: GoogleFonts.inter(
                              color: kLimeGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ] else if (session.isVerified) ...[
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: kLimeGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Verified',
                            style: GoogleFonts.inter(
                              color: kLimeGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  session.device.deviceId,
                  style: GoogleFonts.inter(
                    color: kLightGrey.withValues(alpha: 0.78),
                    fontSize: 10,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            color: kDarkerGrey,
            iconColor: kWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
        ],
      ),
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11171D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 50,
      color: Color(0xFF242B33),
    );
  }

  Widget _deviceIcon(IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          color: kWhite,
          size: 21,
        ),
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
      titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 28),
      actionsPadding: const EdgeInsets.fromLTRB(20, 14, 24, 18),
      title: Text(
        'Rename device',
        style: GoogleFonts.inter(color: kWhite, fontSize: 18),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        cursorColor: kWhite,
        style: GoogleFonts.inter(color: kWhite),
        decoration: _deviceDialogFieldDecoration(
          hintText: 'Device name',
        ),
        onSubmitted: (_) => _close(_controller.text.trim()),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Cancel', style: TextStyle(color: kWhite)),
        ),
        TextButton(
          onPressed: () => _close(_controller.text.trim()),
          child: const Text('Save', style: TextStyle(color: kWhite)),
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
      titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 28),
      actionsPadding: const EdgeInsets.fromLTRB(20, 14, 24, 18),
      title: Text(
        'Confirm password',
        style: GoogleFonts.inter(color: kWhite),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        cursorColor: kWhite,
        style: GoogleFonts.inter(color: kWhite),
        decoration: _deviceDialogFieldDecoration(
          hintText: 'XMO account password',
        ),
        onSubmitted: (_) => _close(_controller.text),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Cancel', style: TextStyle(color: kWhite)),
        ),
        TextButton(
          onPressed: () => _close(_controller.text),
          child: const Text('Continue', style: TextStyle(color: kWhite)),
        ),
      ],
    );
  }
}

InputDecoration _deviceDialogFieldDecoration({required String hintText}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(24),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: Colors.white54),
    isDense: true,
    filled: true,
    fillColor: const Color(0xFF2C2C2E),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: kWhite.withValues(alpha: 0.45), width: 1),
    ),
  );
}
