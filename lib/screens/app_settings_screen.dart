// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../providers/matrix_provider.dart';
import '../providers/story_provider.dart';
import '../services/app_settings_service.dart';
import '../services/direct_chat_service.dart';
import '../services/e2ee_service.dart';
import '../services/privacy_service.dart';
import '../services/push_notification_service.dart';
import '../services/story_service.dart';
import '../theme.dart';
import '../widgets/matrix_chat/fullscreen_video_player.dart';
import '../widgets/story/story_avatar.dart';
import 'app_lock_settings_screen.dart';
import 'device_sessions_screen.dart';
import 'matrix_chat/media_handler.dart';
import 'matrix_chat/widgets/tappable_file_chip.dart';
import 'native_share_stub.dart' if (dart.library.io) 'native_share.dart'
    as native_share;
import 'profile_settings_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final _settingsService = AppSettingsService();
  AppSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  // ignore: unused_element
  Future<void> _updateSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    await _settingsService.save(settings);
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    final current = _settings;
    if (current == null) return;

    final updated = current.copyWith(notificationsEnabled: enabled);
    await _updateSettings(updated);

    if (enabled) {
      await PushNotificationService().registerCurrentUser();
    } else {
      await PushNotificationService().unregisterCurrentUser();
    }
  }

  // ignore: unused_element
  Future<void> _clearMediaCache() async {
    final memoryCount = MediaHandler.memoryCacheCount;
    final count = await _settingsService.clearMediaCache();
    MediaHandler.clearMemoryCache();
    final totalCount = count + memoryCount;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          totalCount == 0
              ? 'Media cache is already empty'
              : 'Cleared $totalCount items',
        ),
        backgroundColor: kLimeGreen,
      ),
    );
  }

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication) ||
        await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open link'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;

    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading || settings == null
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
              children: [
                _navTile(
                  icon: Icons.person,
                  title: 'Account',
                  subtitle: 'Edit your name and profile picture',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileSettingsScreen(),
                      ),
                    );
                  },
                ),
                _navTile(
                  icon: Icons.security,
                  title: 'Security',
                  subtitle: 'Encryption, recovery, and key backup',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SecuritySettingsScreen(),
                      ),
                    );
                  },
                ),
                _navTile(
                  icon: Icons.lock,
                  title: 'Privacy',
                  subtitle: 'Profile photo and story visibility',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacySettingsScreen(),
                      ),
                    );
                  },
                ),
                _switchTile(
                  icon: settings.notificationsEnabled
                      ? Icons.notifications
                      : Icons.notifications_off,
                  title: 'Notifications',
                  subtitle: settings.notificationsEnabled
                      ? 'Messages, media, files, audio, and calls'
                      : 'Notifications are turned off',
                  value: settings.notificationsEnabled,
                  onChanged: _setNotificationsEnabled,
                ),
                _navTile(
                  icon: Icons.block,
                  title: 'Blocked Users',
                  subtitle: 'View and unblock ignored users',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BlockedUsersScreen(),
                      ),
                    );
                  },
                ),
                _navTile(
                  icon: Icons.storage,
                  title: 'Data & Storage',
                  subtitle: 'Manage cached media and storage',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DataStorageScreen(
                          clearMediaCache: _clearMediaCache,
                        ),
                      ),
                    );
                  },
                ),
                _navTile(
                  icon: Icons.description,
                  title: 'Terms of Service',
                  subtitle: 'Read the XMO terms and conditions',
                  onTap: () => _openLegalUrl(
                    'https://xmo.dpdns.org/terms-of-service',
                  ),
                ),
                _navTile(
                  icon: Icons.privacy_tip,
                  title: 'Privacy Policy',
                  subtitle: 'Read how XMO handles privacy and data',
                  onTap: () => _openLegalUrl(
                    'https://xmo.dpdns.org/privacy-policy',
                  ),
                ),
                _infoTile(
                  icon: Icons.info,
                  title: 'Version',
                  value: '1.0.0',
                ),
              ],
            ),
    );
  }

  // ignore: unused_element
  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _settingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Transform.scale(
        scale: 0.82,
        child: Switch(
          value: value,
          activeThumbColor: kLimeGreen,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _settingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return _settingsTile(
      icon: icon,
      title: title,
      subtitle: value,
    );
  }

  // ignore: unused_element
  Widget _choiceTile({
    required IconData icon,
    required String title,
    required String value,
    required Map<String, String> choices,
    required ValueChanged<String> onChanged,
  }) {
    return _settingsTile(
      icon: icon,
      title: title,
      subtitle: choices[value] ?? value,
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: kDarkerGrey,
          value: value,
          iconEnabledColor: kLightGrey,
          items: choices.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    style: GoogleFonts.inter(color: kWhite, fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
        onTap: onTap,
        leading: Icon(icon, color: kWhite, size: 19),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: trailing,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }
}

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  late final E2eeService _e2eeService;
  bool _loading = true;
  bool _working = false;
  E2eeStatus? _status;

  @override
  void initState() {
    super.initState();
    _e2eeService = E2eeService(context.read<MatrixProvider>().service);
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await _e2eeService.getStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _setupRecovery() async {
    final passphrase = await _promptInput(
      title: 'Set up recovery',
      hint: 'Optional passphrase',
      obscure: true,
      message:
          'Leave this empty to create a recovery key only. Store the recovery key somewhere safe.',
    );
    if (passphrase == null || !mounted) return;

    setState(() => _working = true);
    final result = await _e2eeService.setupRecoveryAndKeyBackup(
      passphrase: passphrase,
    );
    if (!mounted) return;
    setState(() => _working = false);
    await _loadStatus();

    if (result.success) {
      await _showRecoveryKey(result.recoveryKey);
    } else {
      _showSnack(result.error ?? 'Recovery setup failed');
    }
  }

  Future<void> _unlockRecovery() async {
    final secret = await _promptInput(
      title: 'Unlock recovery',
      hint: 'Recovery key or passphrase',
      obscure: true,
      message: 'Use your recovery key or passphrase to load key backup.',
    );
    if (secret == null || secret.trim().isEmpty || !mounted) return;

    setState(() => _working = true);
    final result = await _e2eeService.unlockRecoveryAndLoadKeys(secret);
    if (!mounted) return;
    setState(() => _working = false);
    await _loadStatus();
    _showSnack(result.success
        ? 'Recovery unlocked and keys loaded'
        : result.error ?? 'Recovery unlock failed');
  }

  Future<void> _requestSecrets() async {
    setState(() => _working = true);
    try {
      await _e2eeService.requestSecretsFromVerifiedDevices();
      if (mounted) _showSnack('Requested keys from verified devices');
    } catch (e) {
      if (mounted) _showSnack('Unable to request keys: $e');
    } finally {
      if (mounted) {
        setState(() => _working = false);
        await _loadStatus();
      }
    }
  }

  Future<String?> _promptInput({
    required String title,
    required String hint,
    required String message,
    bool obscure = false,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: kDarkerGrey,
          title: Text(
            title,
            style: GoogleFonts.inter(color: kWhite, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: obscure,
                style: GoogleFonts.inter(color: kWhite),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: GoogleFonts.inter(color: kLightGrey),
                  filled: true,
                  fillColor: const Color(0xFF2C2C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: kLightGrey),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(
                'Continue',
                style: GoogleFonts.inter(color: kWhite),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _showRecoveryKey(String? recoveryKey) async {
    if (recoveryKey == null || recoveryKey.isEmpty) {
      _showSnack('Recovery and key backup are ready');
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: kDarkerGrey,
          title: Text(
            'Recovery key',
            style: GoogleFonts.inter(color: kWhite, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save this key. It is needed to recover encrypted messages on another device.',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  recoveryKey,
                  style: GoogleFonts.robotoMono(
                    color: kWhite,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: recoveryKey));
                _showSnack('Recovery key copied');
              },
              child: Text(
                'Copy',
                style: GoogleFonts.inter(color: kWhite),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Done',
                style: GoogleFonts.inter(color: kWhite),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Security',
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
              children: [
                _securityNavTile(
                  icon: Icons.lock,
                  title: 'App Lock',
                  subtitle: 'PIN, biometrics, and automatic locking',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AppLockSettingsScreen(),
                      ),
                    );
                  },
                ),
                _securityNavTile(
                  icon: Icons.devices,
                  title: 'Devices and Sessions',
                  subtitle: 'Review and sign out Matrix sessions',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DeviceSessionsScreen(),
                      ),
                    );
                  },
                ),
                _securityNavTile(
                  icon: Icons.verified_user,
                  title: 'Two-step verification',
                  subtitle: 'Requires homeserver-enforced login support',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TwoFactorStatusScreen(),
                      ),
                    );
                  },
                ),
                const Divider(color: Color(0xFF2C2C2E), height: 28),
                _statusRow(
                  'Encryption',
                  status?.available == true ? 'Available' : 'Unavailable',
                  status?.available == true,
                ),
                _statusRow(
                  'Cross-signing',
                  status?.crossSigningEnabled == true
                      ? status?.crossSigningCached == true
                          ? 'Ready'
                          : 'Needs recovery unlock'
                      : 'Not set up',
                  status?.crossSigningEnabled == true &&
                      status?.crossSigningCached == true,
                ),
                _statusRow(
                  'Key backup',
                  status?.keyBackupEnabled == true
                      ? status?.keyBackupCached == true
                          ? 'Ready'
                          : 'Needs recovery unlock'
                      : 'Not set up',
                  status?.keyBackupEnabled == true &&
                      status?.keyBackupCached == true,
                ),
                _detailRow('Device ID', status?.deviceId ?? 'Unknown'),
                _detailRow('Recovery key ID',
                    status?.defaultRecoveryKeyId ?? 'Not configured'),
                _detailRow('Fingerprint', _shortKey(status?.fingerprintKey)),
                const SizedBox(height: 18),
                _actionButton(
                  'Set up recovery and key backup',
                  _working ? null : _setupRecovery,
                ),
                const SizedBox(height: 10),
                _actionButton(
                  'Unlock recovery',
                  _working ? null : _unlockRecovery,
                ),
                const SizedBox(height: 10),
                _actionButton(
                  'Request keys from verified devices',
                  _working ? null : _requestSecrets,
                  secondary: true,
                ),
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

  Widget _statusRow(String label, String value, bool ok) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle : Icons.info,
        color: ok ? kLimeGreen : kLightGrey,
        size: 19,
      ),
      title: Text(
        label,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        value,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
      ),
    );
  }

  Widget _securityNavTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(icon, color: kWhite, size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: kLightGrey),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: kLightGrey,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: GoogleFonts.inter(color: kWhite, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    VoidCallback? onPressed, {
    bool secondary = false,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: secondary ? const Color(0xFF2C2C2E) : kWhite,
          foregroundColor: secondary ? kWhite : kBlack,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _shortKey(String? key) {
    if (key == null || key.isEmpty) return 'Unavailable';
    if (key.length <= 18) return key;
    return '${key.substring(0, 9)}...${key.substring(key.length - 9)}';
  }
}

class TwoFactorStatusScreen extends StatelessWidget {
  const TwoFactorStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(
          'Two-step verification',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined, color: kWhite, size: 42),
            const SizedBox(height: 18),
            Text(
              'Account 2FA is not enabled',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'XMO currently uses the Matrix homeserver for account login. '
              'Secure two-factor authentication must be enforced by that '
              'server so it cannot be bypassed from another Matrix client.',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'The email code used during registration verifies the email '
              'address; it is not a second factor for every login. App Lock '
              'can protect XMO on this phone while homeserver 2FA is being '
              'deployed.',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  bool _loading = true;
  List<PrivacyContact> _blockedUsers = const [];

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    final provider = context.read<MatrixProvider>();
    final client = provider.service.client;
    final users = <PrivacyContact>[];

    for (final userId in client.ignoredUsers) {
      String displayName = userId;
      String? avatarUrl;
      try {
        final profile = await client.getProfileFromUserId(userId);
        displayName = profile.displayName ?? userId;
        avatarUrl = profile.avatarUrl?.toString();
      } catch (_) {}

      users.add(
        PrivacyContact(
          userId: userId,
          displayName: displayName,
          avatarUrl: avatarUrl,
        ),
      );
    }

    users.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
    );

    if (!mounted) return;
    setState(() {
      _blockedUsers = users;
      _loading = false;
    });
  }

  Future<void> _unblock(String userId) async {
    final service = DirectChatService(context.read<MatrixProvider>().service);
    await service.unblockUser(userId);
    await _loadBlockedUsers();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('User unblocked'),
        backgroundColor: kLimeGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(
          'Blocked Users',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : _blockedUsers.isEmpty
              ? _emptyState(Icons.block, 'No blocked users')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                  itemCount: _blockedUsers.length,
                  itemBuilder: (context, index) {
                    final user = _blockedUsers[index];
                    return _contactTile(
                      user: user,
                      showUserId: false,
                      trailing: TextButton(
                        onPressed: () => _unblock(user.userId),
                        child: Text(
                          'Unblock',
                          style: GoogleFonts.inter(
                            color: kLimeGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  late final PrivacyService _privacyService;
  bool _loading = true;
  bool _saving = false;
  XmoPrivacySettings _settings = const XmoPrivacySettings();
  List<PrivacyContact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _privacyService = PrivacyService(context.read<MatrixProvider>().service);
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _privacyService.loadSettings(),
      _privacyService.getContacts(),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = results[0] as XmoPrivacySettings;
      _contacts = results[1] as List<PrivacyContact>;
      _loading = false;
    });
  }

  Future<void> _save(XmoPrivacySettings settings) async {
    final matrixService = context.read<MatrixProvider>().service;
    final storyProvider = context.read<StoryProvider>();
    setState(() {
      _settings = settings;
      _saving = true;
    });

    try {
      await _privacyService.saveSettings(settings);
      if (mounted) {
        await StoryService(matrixService).applyPrivacySettingsToMyStories(
          settings,
        );
        await storyProvider.refreshStories();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openAudiencePicker({
    required String title,
    required XmoPrivacyAudience audience,
    required List<String> selectedUserIds,
    required ValueChanged<XmoPrivacySettings> apply,
    required XmoPrivacySettings Function(
      XmoPrivacyAudience audience,
      List<String> selectedUserIds,
    ) buildSettings,
  }) async {
    var draftAudience = audience;
    final draftSelected = selectedUserIds.toSet();

    final result = await Navigator.push<XmoPrivacySettings>(
      context,
      MaterialPageRoute(
        builder: (_) => _PrivacyAudiencePickerScreen(
          title: title,
          contacts: _contacts,
          initialAudience: draftAudience,
          initialSelectedUserIds: draftSelected,
          buildSettings: buildSettings,
        ),
      ),
    );

    if (result != null) {
      apply(result);
      await _save(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(
          'Privacy',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: kLimeGreen,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
              children: [
                _accountVisibilityTile(),
                _privacyTile(
                  icon: Icons.account_circle,
                  title: 'Profile Picture',
                  subtitle: _privacySummary(
                    _settings.profileAvatarAudience,
                    _settings.profileAvatarUserIds,
                  ),
                  onTap: () => _openAudiencePicker(
                    title: 'Profile Picture',
                    audience: _settings.profileAvatarAudience,
                    selectedUserIds: _settings.profileAvatarUserIds,
                    apply: (settings) => _settings = settings,
                    buildSettings: (audience, selectedUserIds) {
                      return _settings.copyWith(
                        profileAvatarAudience: audience,
                        profileAvatarUserIds: selectedUserIds,
                      );
                    },
                  ),
                ),
                _privacyTile(
                  icon: Icons.auto_stories,
                  title: 'Stories',
                  subtitle: _privacySummary(
                    _settings.storyAudience,
                    _settings.storyUserIds,
                  ),
                  onTap: () => _openAudiencePicker(
                    title: 'Stories',
                    audience: _settings.storyAudience,
                    selectedUserIds: _settings.storyUserIds,
                    apply: (settings) => _settings = settings,
                    buildSettings: (audience, selectedUserIds) {
                      return _settings.copyWith(
                        storyAudience: audience,
                        storyUserIds: selectedUserIds,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _accountVisibilityTile() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
        leading: Icon(
          _settings.accountIsPublic ? Icons.public : Icons.lock,
          color: kWhite,
          size: 19,
        ),
        title: Text(
          'Account Visibility',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _settings.accountIsPublic
              ? 'Public account appears in XMO user search'
              : 'Private account is hidden from XMO user search',
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch(
          value: _settings.accountIsPublic,
          activeThumbColor: kLimeGreen,
          onChanged: _saving
              ? null
              : (value) {
                  _save(_settings.copyWith(accountIsPublic: value));
                },
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }

  String _privacySummary(XmoPrivacyAudience audience, List<String> userIds) {
    switch (audience) {
      case XmoPrivacyAudience.contacts:
        return 'All contacts';
      case XmoPrivacyAudience.onlySelected:
        return userIds.isEmpty
            ? 'No contacts selected'
            : 'Only ${userIds.length} selected contacts';
      case XmoPrivacyAudience.hideSelected:
        return userIds.isEmpty
            ? 'All contacts'
            : 'Hidden from ${userIds.length} selected contacts';
    }
  }

  Widget _privacyTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
        onTap: onTap,
        leading: Icon(icon, color: kWhite, size: 19),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right, color: kLightGrey, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }
}

class _PrivacyAudiencePickerScreen extends StatefulWidget {
  final String title;
  final List<PrivacyContact> contacts;
  final XmoPrivacyAudience initialAudience;
  final Set<String> initialSelectedUserIds;
  final XmoPrivacySettings Function(
    XmoPrivacyAudience audience,
    List<String> selectedUserIds,
  ) buildSettings;

  const _PrivacyAudiencePickerScreen({
    required this.title,
    required this.contacts,
    required this.initialAudience,
    required this.initialSelectedUserIds,
    required this.buildSettings,
  });

  @override
  State<_PrivacyAudiencePickerScreen> createState() =>
      _PrivacyAudiencePickerScreenState();
}

class _PrivacyAudiencePickerScreenState
    extends State<_PrivacyAudiencePickerScreen> {
  late XmoPrivacyAudience _audience;
  late Set<String> _selectedUserIds;

  @override
  void initState() {
    super.initState();
    _audience = widget.initialAudience;
    _selectedUserIds = {...widget.initialSelectedUserIds};
  }

  bool get _usesSelection => _audience != XmoPrivacyAudience.contacts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                context,
                widget.buildSettings(_audience, _selectedUserIds.toList()),
              );
            },
            child: Text(
              'Save',
              style: GoogleFonts.inter(
                color: kLimeGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
        children: [
          _radioTile(
            title: 'All Contacts',
            subtitle: 'Every contact can view this',
            value: XmoPrivacyAudience.contacts,
          ),
          _radioTile(
            title: 'Only Selected Contacts',
            subtitle: 'Only the people selected below can view this',
            value: XmoPrivacyAudience.onlySelected,
          ),
          _radioTile(
            title: 'Hide From Selected Contacts',
            subtitle: 'Everyone except the people selected below can view this',
            value: XmoPrivacyAudience.hideSelected,
          ),
          if (_usesSelection) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Text(
                'Contacts',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (widget.contacts.isEmpty)
              _emptyState(Icons.contacts, 'No contacts yet')
            else
              ...widget.contacts.map((contact) {
                final selected = _selectedUserIds.contains(contact.userId);
                return _contactTile(
                  user: contact,
                  trailing: Checkbox(
                    value: selected,
                    activeColor: kLimeGreen,
                    onChanged: (_) => _toggle(contact.userId),
                  ),
                  onTap: () => _toggle(contact.userId),
                );
              }),
          ],
        ],
      ),
    );
  }

  Widget _radioTile({
    required String title,
    required String subtitle,
    required XmoPrivacyAudience value,
  }) {
    return RadioListTile<XmoPrivacyAudience>(
      value: value,
      groupValue: _audience,
      activeColor: kLimeGreen,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _audience = value);
      },
    );
  }

  void _toggle(String userId) {
    setState(() {
      if (!_selectedUserIds.add(userId)) {
        _selectedUserIds.remove(userId);
      }
    });
  }
}

Widget _contactTile({
  required PrivacyContact user,
  Widget? trailing,
  VoidCallback? onTap,
  bool showUserId = true,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
      onTap: onTap,
      leading: StoryAvatar(
        userName: user.displayName,
        avatarUrl: user.avatarUrl,
        size: 36,
        backgroundColor: kMediumGrey,
      ),
      title: Text(
        user.displayName,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: showUserId
          ? Text(
              user.userId,
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    ),
  );
}

Widget _emptyState(IconData icon, String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kLightGrey, size: 42),
          const SizedBox(height: 12),
          Text(
            text,
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class DataStorageScreen extends StatefulWidget {
  final Future<void> Function() clearMediaCache;

  const DataStorageScreen({
    super.key,
    required this.clearMediaCache,
  });

  @override
  State<DataStorageScreen> createState() => _DataStorageScreenState();
}

class _DataStorageScreenState extends State<DataStorageScreen> {
  bool _loading = true;
  bool _clearingCache = false;
  _StorageReport _report = _StorageReport.empty();

  @override
  void initState() {
    super.initState();
    _loadStorage();
  }

  Future<String> _downloadsPath() async {
    final baseDir =
        Platform.isAndroid ? await getExternalStorageDirectory() : null;
    final directory = Directory(
      '${(baseDir ?? await getApplicationDocumentsDirectory()).path}/XMO Downloads',
    );
    return directory.path;
  }

  Future<void> _loadStorage() async {
    final provider = context.read<MatrixProvider>();
    final categorySizes = {
      _StorageCategoryType.videos: 0,
      _StorageCategoryType.audio: 0,
      _StorageCategoryType.photos: 0,
      _StorageCategoryType.files: 0,
    };
    final downloadFiles = <_DownloadedStorageFile>[];

    final downloadsDirectory = Directory(await _downloadsPath());
    if (await downloadsDirectory.exists()) {
      await for (final entity in downloadsDirectory.list(recursive: true)) {
        if (entity is! File) continue;
        final size = await entity.length();
        final category = _categoryForFile(entity.path);
        categorySizes[category] = (categorySizes[category] ?? 0) + size;
        downloadFiles.add(
          _DownloadedStorageFile(
            name: _fileNameFromPath(entity.path),
            path: entity.path,
            type: category,
            bytes: size,
          ),
        );
      }
    }

    final cacheBytes = _mediaCacheBytes();
    final roomStats = await _loadRoomStats(provider, downloadFiles);

    if (!mounted) return;
    setState(() {
      _report = _StorageReport(
        categories: _buildCategories(categorySizes),
        cacheBytes: cacheBytes,
        roomStats: roomStats,
        downloadFiles: downloadFiles
          ..sort((a, b) => b.bytes.compareTo(a.bytes)),
      );
      _loading = false;
    });
  }

  int _mediaCacheBytes() {
    if (!Hive.isBoxOpen('xmo_media_cache')) return 0;
    final box = Hive.box<Uint8List>('xmo_media_cache');
    return box.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
  }

  List<_StorageCategory> _buildCategories(
    Map<_StorageCategoryType, int> sizes,
  ) {
    return [
      _StorageCategory(
        type: _StorageCategoryType.videos,
        label: 'Videos',
        icon: Icons.videocam,
        color: const Color(0xFF3B82F6),
        bytes: sizes[_StorageCategoryType.videos] ?? 0,
      ),
      _StorageCategory(
        type: _StorageCategoryType.audio,
        label: 'Audio',
        icon: Icons.audiotrack,
        color: const Color(0xFFF59E0B),
        bytes: sizes[_StorageCategoryType.audio] ?? 0,
      ),
      _StorageCategory(
        type: _StorageCategoryType.photos,
        label: 'Photos',
        icon: Icons.photo,
        color: const Color(0xFF22C55E),
        bytes: sizes[_StorageCategoryType.photos] ?? 0,
      ),
      _StorageCategory(
        type: _StorageCategoryType.files,
        label: 'Files',
        icon: Icons.description,
        color: const Color(0xFFA855F7),
        bytes: sizes[_StorageCategoryType.files] ?? 0,
      ),
    ];
  }

  Future<List<_RoomStorageStat>> _loadRoomStats(
    MatrixProvider provider,
    List<_DownloadedStorageFile> downloadFiles,
  ) async {
    final stats = <_RoomStorageStat>[];
    final downloadedByKey = <String, List<_DownloadedStorageFile>>{};
    for (final file in downloadFiles) {
      final key = _downloadMatchKey(
        file.type,
        file.name,
        file.bytes,
      );
      downloadedByKey.putIfAbsent(key, () => []).add(file);
    }

    for (final room in provider.rooms) {
      if (room.membership != Membership.join) continue;

      final categoryBytes = {
        _StorageCategoryType.videos: 0,
        _StorageCategoryType.audio: 0,
        _StorageCategoryType.photos: 0,
        _StorageCategoryType.files: 0,
      };
      final roomFiles = <_DownloadedStorageFile>[];
      try {
        final timeline = await room.getTimeline();
        for (final event in timeline.events) {
          if (event.redacted || event.type != EventTypes.Message) continue;
          final size = _eventMediaSize(event);
          final category = _eventMediaCategory(event);
          final fileName = _eventMediaFileName(event);
          if (size > 0 && category != null && fileName != null) {
            final file = _takeDownloadedMatch(
              downloadedByKey,
              category,
              fileName,
              size,
            );
            if (file != null) {
              roomFiles.add(file);
              categoryBytes[category] =
                  (categoryBytes[category] ?? 0) + file.bytes;
            }
          }
        }
      } catch (e) {
        debugPrint('[Storage] Failed to read timeline for ${room.id}: $e');
      }

      final bytes =
          categoryBytes.values.fold<int>(0, (sum, size) => sum + size);
      if (bytes <= 0) continue;
      final isSavedMessages = provider.service.isSavedMessagesRoom(room);
      final kind = isSavedMessages
          ? _RoomStorageKind.saved
          : room.isDirectChat
              ? _RoomStorageKind.chats
              : room.isChannel
                  ? _RoomStorageKind.channels
                  : _RoomStorageKind.groups;
      stats.add(
        _RoomStorageStat(
          room: room,
          name: isSavedMessages
              ? 'Saved Messages'
              : provider.service.getResolvedDisplayName(room),
          avatarUrl: room.avatar?.toString(),
          kind: kind,
          bytes: bytes,
          categoryBytes: categoryBytes,
          downloadedFiles: roomFiles,
        ),
      );
    }

    stats.sort((a, b) => b.bytes.compareTo(a.bytes));
    return stats;
  }

  _DownloadedStorageFile? _takeDownloadedMatch(
    Map<String, List<_DownloadedStorageFile>> downloadedByKey,
    _StorageCategoryType category,
    String fileName,
    int bytes,
  ) {
    final key = _downloadMatchKey(category, fileName, bytes);
    final matches = downloadedByKey[key];
    if (matches == null || matches.isEmpty) return null;
    final file = matches.removeLast();
    if (matches.isEmpty) downloadedByKey.remove(key);
    return file;
  }

  String _downloadMatchKey(
    _StorageCategoryType category,
    String fileName,
    int bytes,
  ) {
    return '${category.name}|${_normalizedFileName(fileName)}|$bytes';
  }

  String _normalizedFileName(String fileName) {
    return _fileNameFromPath(fileName).trim().toLowerCase();
  }

  int _eventMediaSize(Event event) {
    final msgType = event.messageType;
    if (msgType != MessageTypes.Image &&
        msgType != MessageTypes.Video &&
        msgType != MessageTypes.Audio &&
        msgType != MessageTypes.File) {
      return 0;
    }

    final info = event.content['info'];
    if (info is Map) {
      final size = info['size'];
      if (size is int) return size;
      if (size is num) return size.toInt();
    }
    return 0;
  }

  _StorageCategoryType? _eventMediaCategory(Event event) {
    switch (event.messageType) {
      case MessageTypes.Video:
        return _StorageCategoryType.videos;
      case MessageTypes.Audio:
        return _StorageCategoryType.audio;
      case MessageTypes.Image:
        return _StorageCategoryType.photos;
      case MessageTypes.File:
        return _StorageCategoryType.files;
      default:
        return null;
    }
  }

  String? _eventMediaFileName(Event event) {
    final filename = event.content['filename'];
    if (filename is String && filename.trim().isNotEmpty) {
      return filename;
    }
    final body = event.content['body'];
    if (body is String && body.trim().isNotEmpty) {
      return body;
    }
    return null;
  }

  _StorageCategoryType _categoryForFile(String path) {
    final folderCategory = _categoryFromDownloadFolder(path);
    if (folderCategory != null) return folderCategory;

    final lower = path.toLowerCase();
    if (_hasExtension(lower, const [
      '.mp4',
      '.mov',
      '.mkv',
      '.webm',
      '.avi',
      '.3gp',
    ])) {
      return _StorageCategoryType.videos;
    }
    if (_hasExtension(lower, const [
      '.mp3',
      '.m4a',
      '.aac',
      '.wav',
      '.ogg',
      '.opus',
      '.flac',
    ])) {
      return _StorageCategoryType.audio;
    }
    if (_hasExtension(lower, const [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.gif',
      '.heic',
    ])) {
      return _StorageCategoryType.photos;
    }
    return _StorageCategoryType.files;
  }

  _StorageCategoryType? _categoryFromDownloadFolder(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    if (normalized.contains('/xmo downloads/files/')) {
      return _StorageCategoryType.files;
    }
    if (normalized.contains('/xmo downloads/videos/')) {
      return _StorageCategoryType.videos;
    }
    if (normalized.contains('/xmo downloads/audio/')) {
      return _StorageCategoryType.audio;
    }
    if (normalized.contains('/xmo downloads/photos/')) {
      return _StorageCategoryType.photos;
    }
    return null;
  }

  bool _hasExtension(String path, List<String> extensions) {
    return extensions.any(path.endsWith);
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  Future<void> _clearDownloadsAndCache() async {
    if (_clearingCache) return;

    setState(() => _clearingCache = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final directory = Directory(await _downloadsPath());
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File && await entity.exists()) {
            await entity.delete();
          }
        }
      }

      await widget.clearMediaCache();
      if (!mounted) return;
      setState(() {
        _report = _StorageReport.empty();
      });
      await _loadStorage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to clear cache: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _clearingCache = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: Text(
          'Storage Usage',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : RefreshIndicator(
              color: kLimeGreen,
              backgroundColor: kDarkerGrey,
              onRefresh: _loadStorage,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
                children: [
                  _buildUsageSummary(),
                  const SizedBox(height: 18),
                  _buildCategoryList(),
                  const SizedBox(height: 14),
                  _buildClearButton(),
                  const SizedBox(height: 22),
                  _buildStorageDetails(),
                ],
              ),
            ),
    );
  }

  Widget _buildUsageSummary() {
    return Column(
      children: [
        SizedBox(
          width: 176,
          height: 176,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(176),
                painter: _StorageRingPainter(_report.visibleCategories),
              ),
              Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  color: kDarkerGrey,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _formatBytes(_report.downloadBytes),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Storage Usage',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _report.cacheBytes > 0
              ? '${_formatBytes(_report.cacheBytes)} cached media previews'
              : 'Downloaded media in XMO Downloads',
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCategoryList() {
    return Column(
      children: _report.categories.map((category) {
        final percent = _report.downloadBytes == 0
            ? 0
            : ((category.bytes / _report.downloadBytes) * 100).round();
        return ListTile(
          minLeadingWidth: 28,
          leading: CircleAvatar(
            radius: 13,
            backgroundColor: category.color,
            child: Icon(category.icon, color: kWhite, size: 15),
          ),
          title: Text(
            '${category.label}  $percent%',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Text(
            _formatBytes(category.bytes),
            style: GoogleFonts.inter(
              color: const Color(0xFF3B82F6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 0),
        );
      }).toList(),
    );
  }

  Widget _buildClearButton() {
    return SizedBox(
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: kLimeGreen,
          foregroundColor: kBlack,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _report.totalBytes == 0 || _clearingCache
            ? null
            : _clearDownloadsAndCache,
        child: _clearingCache
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kBlack,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Clearing...',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ],
              )
            : Text(
                'Clear Cache  ${_formatBytes(_report.totalBytes)}',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildStorageDetails() {
    return DefaultTabController(
      length: _StorageTab.values.length,
      child: Column(
        children: [
          _buildRoomTabs(),
          SizedBox(
            height: _storageTabViewHeight(),
            child: TabBarView(
              children: _StorageTab.values.map((tab) {
                if (tab == _StorageTab.chats) {
                  return SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: _buildChatStorageList(),
                  );
                }
                return SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: _buildDownloadFileList(tab),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  double _storageTabViewHeight() {
    final heights = _StorageTab.values.map((tab) {
      if (tab == _StorageTab.chats) {
        final count = math.max(_report.roomStats.length, 1);
        return count * 62.0 + 68.0;
      }
      final files = _filesForStorageTab(tab)
        ..sort((a, b) => b.bytes.compareTo(a.bytes));
      if (files.isEmpty) return 96.0;
      final category = tab.category!;
      if (category == _StorageCategoryType.photos ||
          category == _StorageCategoryType.videos) {
        final rows = (files.length / 3).ceil();
        return rows * 124.0 + 24.0;
      }
      return files.length * 62.0 + 24.0;
    });
    return heights.fold<double>(96.0, math.max).clamp(96.0, 720.0);
  }

  Widget _buildChatStorageList() {
    final stats = [..._report.roomStats]
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
    if (stats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Text(
          'No chat media storage found',
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
        ),
      );
    }
    return Column(children: stats.map(_buildRoomStorageTile).toList());
  }

  Widget _buildDownloadFileList(_StorageTab tab) {
    final category = tab.category!;
    final files = _filesForStorageTab(tab)
      ..sort((a, b) => b.bytes.compareTo(a.bytes));

    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Text(
          'No downloaded ${tab.label.toLowerCase()} found',
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
        ),
      );
    }

    if (category == _StorageCategoryType.photos ||
        category == _StorageCategoryType.videos) {
      return _buildDownloadedMediaGrid(files, category);
    }

    return Column(children: files.map(_buildDownloadFileTile).toList());
  }

  List<_DownloadedStorageFile> _filesForStorageTab(_StorageTab tab) {
    final category = tab.category;
    if (category == null) return const [];
    return _report.downloadFiles
        .where((file) => file.type == category)
        .toList();
  }

  Widget _buildDownloadedMediaGrid(
    List<_DownloadedStorageFile> files,
    _StorageCategoryType category,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: files.length,
      itemBuilder: (_, index) => _buildDownloadedMediaTile(
        files[index],
        category,
      ),
    );
  }

  Widget _buildDownloadedMediaTile(
    _DownloadedStorageFile file,
    _StorageCategoryType category,
  ) {
    final isVideo = category == _StorageCategoryType.videos;
    return GestureDetector(
      onTap: () => _openDownloadedMedia(file),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(color: kDarkerGrey),
              child: isVideo
                  ? _DownloadedVideoThumbnail(file: file)
                  : Image.file(
                      File(file.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.image, color: kLimeGreen, size: 30),
                      ),
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.68),
                    ],
                  ),
                ),
                child: Text(
                  _formatBytes(file.bytes),
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (isVideo)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: kWhite,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadFileTile(_DownloadedStorageFile file) {
    final category = _categoryForType(file.type);
    final mimeType = lookupMimeType(file.path) ?? lookupMimeType(file.name);
    final attachmentType = attachmentTypeFor(
      mimeType: mimeType,
      fileName: file.name,
    );
    if (file.type == _StorageCategoryType.audio) {
      return _DownloadedAudioTile(
        file: file,
        formatBytes: _formatBytes,
      );
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: category.color.withValues(alpha: 0.18),
        child: Icon(attachmentType.icon, color: category.color, size: 21),
      ),
      title: Text(
        file.name,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text(
            '${_formatBytes(file.bytes)} • ',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
          ),
          Flexible(
            child: Text(
              attachmentType.label,
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0.5),
      onTap: () => _openDownloadedFile(file),
    );
  }

  Future<void> _openDownloadedMedia(_DownloadedStorageFile file) async {
    try {
      final bytes = await File(file.path).readAsBytes();
      if (!mounted) return;

      if (file.type == _StorageCategoryType.photos) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _DownloadedImageViewer(
              imageBytes: bytes,
              title: file.name,
              mimeType: lookupMimeType(file.path, headerBytes: bytes),
            ),
          ),
        );
        return;
      }

      if (file.type == _StorageCategoryType.videos) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullscreenVideoPlayer(
              videoBytes: bytes,
              mimeType: lookupMimeType(file.path, headerBytes: bytes),
              title: file.name,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open media: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openDownloadedFile(_DownloadedStorageFile file) async {
    try {
      final bytes = await File(file.path).readAsBytes();
      final mimeType = lookupMimeType(file.path, headerBytes: bytes);

      if (!mounted) return;

      if (mimeType?.startsWith('image/') == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _DownloadedImageViewer(
              imageBytes: bytes,
              title: file.name,
              mimeType: mimeType,
            ),
          ),
        );
        return;
      }

      if (mimeType?.startsWith('video/') == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullscreenVideoPlayer(
              videoBytes: bytes,
              mimeType: mimeType,
              title: file.name,
            ),
          ),
        );
        return;
      }

      await native_share.openFile(
        bytes,
        file.name,
        mimeType: mimeType,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  _StorageCategory _categoryForType(_StorageCategoryType type) {
    return _report.categories.firstWhere((category) => category.type == type);
  }

  Widget _buildRoomTabs() {
    return TabBar(
      indicatorColor: kLimeGreen,
      dividerColor: Colors.transparent,
      labelColor: kLimeGreen,
      unselectedLabelColor: kLightGrey,
      labelPadding: EdgeInsets.zero,
      labelStyle: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      tabs: _StorageTab.values.map((tab) => Tab(text: tab.label)).toList(),
    );
  }

  Widget _buildRoomStorageTile(_RoomStorageStat stat) {
    final bytes = stat.bytes;
    return ListTile(
      leading: StoryAvatar(
        userName: stat.name,
        avatarUrl: stat.avatarUrl,
        size: 44,
        backgroundColor: kMediumGrey,
        fallbackIcon: stat.kind.icon,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              stat.name,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (stat.kind == _RoomStorageKind.groups ||
              stat.kind == _RoomStorageKind.channels) ...[
            const SizedBox(width: 8),
            _StorageRoomKindBadge(kind: stat.kind),
          ],
        ],
      ),
      trailing: Text(
        _formatBytes(bytes),
        style: GoogleFonts.inter(
          color: const Color(0xFF3B82F6),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      onTap: () => _showRoomStorageSheet(stat),
    );
  }

  void _showRoomStorageSheet(_RoomStorageStat stat) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return DefaultTabController(
          length: 4,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.72,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kMediumGrey,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),
                  StoryAvatar(
                    userName: stat.name,
                    avatarUrl: stat.avatarUrl,
                    size: 70,
                    backgroundColor: kMediumGrey,
                    fallbackIcon: stat.kind.icon,
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Text(
                      stat.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatBytes(stat.bytes),
                    style: GoogleFonts.inter(
                      color: const Color(0xFF3B82F6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    indicatorColor: kLimeGreen,
                    dividerColor: Colors.transparent,
                    labelColor: kLimeGreen,
                    unselectedLabelColor: kLightGrey,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(text: 'Photos'),
                      Tab(text: 'Videos'),
                      Tab(text: 'Audio'),
                      Tab(text: 'Files'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildRoomMediaTab(stat, _StorageCategoryType.photos),
                        _buildRoomMediaTab(stat, _StorageCategoryType.videos),
                        _buildRoomMediaTab(stat, _StorageCategoryType.audio),
                        _buildRoomMediaTab(stat, _StorageCategoryType.files),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoomMediaTab(
    _RoomStorageStat stat,
    _StorageCategoryType category,
  ) {
    final files = stat.downloadedFiles
        .where((file) => file.type == category)
        .toList()
      ..sort((a, b) => b.bytes.compareTo(a.bytes));

    if (files.isEmpty) {
      return Center(
        child: Text(
          'No downloaded ${_categoryForType(category).label.toLowerCase()}',
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
        ),
      );
    }

    if (category == _StorageCategoryType.photos ||
        category == _StorageCategoryType.videos) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: files.length,
        itemBuilder: (_, index) => _buildDownloadedMediaTile(
          files[index],
          category,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      itemCount: files.length,
      itemBuilder: (_, index) => _buildDownloadFileTile(files[index]),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    if (unitIndex == 0) return '${value.round()} ${units[unitIndex]}';
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unitIndex]}';
  }
}

enum _StorageCategoryType { videos, audio, photos, files }

enum _StorageTab {
  chats('Chats', null),
  photos('Photos', _StorageCategoryType.photos),
  videos('Videos', _StorageCategoryType.videos),
  audio('Audio', _StorageCategoryType.audio),
  files('Files', _StorageCategoryType.files);

  final String label;
  final _StorageCategoryType? category;

  const _StorageTab(this.label, this.category);
}

class _StorageCategory {
  final _StorageCategoryType type;
  final String label;
  final IconData icon;
  final Color color;
  final int bytes;

  const _StorageCategory({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
    required this.bytes,
  });
}

class _DownloadedStorageFile {
  final String name;
  final String path;
  final _StorageCategoryType type;
  final int bytes;

  const _DownloadedStorageFile({
    required this.name,
    required this.path,
    required this.type,
    required this.bytes,
  });
}

class _DownloadedVideoThumbnail extends StatefulWidget {
  final _DownloadedStorageFile file;

  const _DownloadedVideoThumbnail({required this.file});

  @override
  State<_DownloadedVideoThumbnail> createState() =>
      _DownloadedVideoThumbnailState();
}

class _DownloadedVideoThumbnailState extends State<_DownloadedVideoThumbnail> {
  late Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _DownloadedVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _thumbnailFuture = _loadThumbnail();
    }
  }

  Future<Uint8List?> _loadThumbnail() {
    return VideoThumbnail.thumbnailData(
      video: widget.file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 256,
      quality: 70,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, fit: BoxFit.cover);
        }

        return const Center(
          child: Icon(Icons.videocam, color: kLimeGreen, size: 30),
        );
      },
    );
  }
}

class _DownloadedAudioTile extends StatefulWidget {
  final _DownloadedStorageFile file;
  final String Function(int bytes) formatBytes;

  const _DownloadedAudioTile({
    required this.file,
    required this.formatBytes,
  });

  @override
  State<_DownloadedAudioTile> createState() => _DownloadedAudioTileState();
}

class _DownloadedAudioTileState extends State<_DownloadedAudioTile> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  bool _ready = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    _positionSub = _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration ?? Duration.zero);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    try {
      if (!_ready) {
        setState(() => _loading = true);
        await _player.setFilePath(widget.file.path);
        if (!mounted) return;
        setState(() {
          _ready = true;
          _loading = false;
        });
      }

      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not play audio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _seekToProgress(double value) async {
    if (!_ready || _duration <= Duration.zero) return;
    await _player.seek(
      Duration(milliseconds: (_duration.inMilliseconds * value).round()),
    );
  }

  Widget _buildProgressControl(double progress) {
    return SizedBox(
      height: 18,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        ),
        child: Slider(
          value: progress,
          min: 0,
          max: 1,
          activeColor: kLimeGreen,
          inactiveColor: kMediumGrey,
          onChanged: _ready && _duration > Duration.zero
              ? (value) => _seekToProgress(value)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    final sizeStr = widget.formatBytes(widget.file.bytes);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
        minLeadingWidth: 38,
        contentPadding: EdgeInsets.zero,
        leading: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 42, height: 42),
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: kLimeGreen,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: kLimeGreen,
                  size: 40,
                ),
          onPressed: _loading ? null : _togglePlayback,
        ),
        title: Text(
          widget.file.name,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressControl(progress),
            Text(
              sizeStr,
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadedImageViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;
  final String? mimeType;

  const _DownloadedImageViewer({
    required this.imageBytes,
    required this.title,
    required this.mimeType,
  });

  Future<void> _share(BuildContext context) async {
    try {
      await native_share.shareFile(
        imageBytes,
        title,
        mimeType: mimeType,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: kWhite),
            onPressed: () => _share(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(imageBytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _StorageRoomKindBadge extends StatelessWidget {
  final _RoomStorageKind kind;

  const _StorageRoomKindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final isChannel = kind == _RoomStorageKind.channels;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isChannel ? Icons.campaign : Icons.group,
            color: kLimeGreen,
            size: 10,
          ),
          const SizedBox(width: 2),
          Text(
            isChannel ? 'Channel' : 'Group',
            style: GoogleFonts.inter(
              color: kLimeGreen,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _RoomStorageKind {
  chats('Chats', 'Chat', Icons.chat),
  saved('Saved Messages', 'Saved', Icons.bookmark),
  groups('Groups', 'Group', Icons.group),
  channels('Channels', 'Channel', Icons.campaign);

  final String label;
  final String singularLabel;
  final IconData icon;

  const _RoomStorageKind(this.label, this.singularLabel, this.icon);
}

class _RoomStorageStat {
  final Room room;
  final String name;
  final String? avatarUrl;
  final _RoomStorageKind kind;
  final int bytes;
  final Map<_StorageCategoryType, int> categoryBytes;
  final List<_DownloadedStorageFile> downloadedFiles;

  const _RoomStorageStat({
    required this.room,
    required this.name,
    required this.avatarUrl,
    required this.kind,
    required this.bytes,
    required this.categoryBytes,
    required this.downloadedFiles,
  });

  int bytesFor(_StorageCategoryType category) => categoryBytes[category] ?? 0;
}

class _StorageReport {
  final List<_StorageCategory> categories;
  final int cacheBytes;
  final List<_RoomStorageStat> roomStats;
  final List<_DownloadedStorageFile> downloadFiles;

  const _StorageReport({
    required this.categories,
    required this.cacheBytes,
    required this.roomStats,
    required this.downloadFiles,
  });

  factory _StorageReport.empty() {
    return const _StorageReport(
      categories: [],
      cacheBytes: 0,
      roomStats: [],
      downloadFiles: [],
    );
  }

  int get downloadBytes {
    return categories.fold<int>(0, (sum, category) => sum + category.bytes);
  }

  int get totalBytes => downloadBytes + cacheBytes;

  List<_StorageCategory> get visibleCategories {
    return categories.where((category) => category.bytes > 0).toList();
  }
}

class _StorageRingPainter extends CustomPainter {
  final List<_StorageCategory> categories;

  const _StorageRingPainter(this.categories);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius - 7);
    final strokeWidth = radius * 0.32;

    final backgroundPaint = Paint()
      ..color = kMediumGrey
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, backgroundPaint);

    final total = categories.fold<int>(
      0,
      (sum, category) => sum + category.bytes,
    );
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final category in categories) {
      final sweep = (category.bytes / total) * math.pi * 2;
      final paint = Paint()
        ..color = category.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _StorageRingPainter oldDelegate) {
    return oldDelegate.categories != categories;
  }
}
