import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../services/app_settings_service.dart';
import '../services/matrix_service.dart';
import '../theme.dart';
import 'matrix_chat/media_handler.dart';
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

  Future<void> _updateSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    await _settingsService.save(settings);
  }

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
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading || settings == null
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
              children: [
                _sectionTitle('Account'),
                _navTile(
                  icon: Icons.person_outline,
                  title: 'My Profile',
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
                _infoTile(
                  icon: Icons.alternate_email,
                  title: 'User ID',
                  value: context.read<MatrixProvider>().userId ?? '',
                ),
                _sectionTitle('Notifications'),
                _switchTile(
                  icon: Icons.notifications_outlined,
                  title: 'Message notifications',
                  subtitle: 'Receive alerts for new messages',
                  value: settings.notificationsEnabled,
                  onChanged: (value) => _updateSettings(
                    settings.copyWith(notificationsEnabled: value),
                  ),
                ),
                _sectionTitle('Privacy'),
                _switchTile(
                  icon: Icons.done_all,
                  title: 'Read receipts',
                  subtitle: 'Allow others to know when you read messages',
                  value: settings.readReceiptsEnabled,
                  onChanged: (value) => _updateSettings(
                    settings.copyWith(readReceiptsEnabled: value),
                  ),
                ),
                _switchTile(
                  icon: Icons.keyboard_alt_outlined,
                  title: 'Typing indicators',
                  subtitle: 'Show when you are typing',
                  value: settings.typingIndicatorsEnabled,
                  onChanged: (value) => _updateSettings(
                    settings.copyWith(typingIndicatorsEnabled: value),
                  ),
                ),
                _sectionTitle('Media'),
                _switchTile(
                  icon: Icons.perm_media_outlined,
                  title: 'Auto-download media',
                  subtitle: 'Preload images and video thumbnails',
                  value: settings.autoDownloadMedia,
                  onChanged: (value) => _updateSettings(
                    settings.copyWith(autoDownloadMedia: value),
                  ),
                ),
                _navTile(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Clear media cache',
                  subtitle: 'Remove cached images and thumbnails',
                  onTap: _clearMediaCache,
                ),
                _sectionTitle('Chats'),
                _choiceTile(
                  icon: Icons.filter_list,
                  title: 'Default tab',
                  value: settings.defaultChatFilter,
                  choices: const {
                    'all': 'All',
                    'stories': 'Stories',
                    'groups': 'Groups',
                    'channels': 'Channels',
                  },
                  onChanged: (value) => _updateSettings(
                    settings.copyWith(defaultChatFilter: value),
                  ),
                ),
                _sectionTitle('About'),
                _infoTile(
                  icon: Icons.dns_outlined,
                  title: 'Homeserver',
                  value: MatrixService.homeserverUrl,
                ),
                _infoTile(
                  icon: Icons.info_outline,
                  title: 'Version',
                  value: '1.0.0',
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: kLightGrey,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

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
      trailing: const Icon(Icons.chevron_right, color: kLightGrey),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
        onTap: onTap,
        leading: Icon(icon, color: kLimeGreen, size: 19),
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
