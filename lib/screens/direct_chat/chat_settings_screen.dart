import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/direct_chat_service.dart';
import '../../models/direct_chat_models.dart';
import '../../widgets/incoming_call_fullscreen_scope.dart';

/// Chat Settings Screen for Direct Chats
class ChatSettingsScreen extends StatefulWidget {
  final Room room;

  const ChatSettingsScreen({super.key, required this.room});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  late DirectChatService _directChatService;
  DirectChatSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _directChatService = DirectChatService(matrixProvider.service);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final settings = await _directChatService.getChatSettings(widget.room.id);
      if (mounted) {
        setState(() {
          _settings = settings;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[ChatSettings] Error loading settings: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _updateSettings(DirectChatSettings newSettings) async {
    try {
      await _directChatService.updateChatSettings(widget.room.id, newSettings);
      if (mounted) {
        setState(() => _settings = newSettings);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings updated'),
            backgroundColor: kLimeGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(safeUserFacingText('Failed to update settings: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IncomingCallFullscreenScope(
      child: Scaffold(
        backgroundColor: kBlack,
        appBar: AppBar(
          backgroundColor: kBlack,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kWhite),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Chat Settings',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
            : _settings == null
            ? Center(
                child: Text(
                  'Failed to load settings',
                  style: GoogleFonts.inter(color: kLightGrey),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // Notifications Section
                    _buildSection(
                      title: 'Notifications',
                      children: [
                        _buildSwitchTile(
                          icon: Icons.notifications_outlined,
                          title: 'Notifications',
                          subtitle: 'Receive notifications for new messages',
                          value: _settings!.notificationsEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings!.copyWith(notificationsEnabled: value),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Privacy Section
                    _buildSection(
                      title: 'Privacy',
                      children: [
                        _buildSwitchTile(
                          icon: Icons.done_all,
                          title: 'Read Receipts',
                          subtitle:
                              'Let others know when you\'ve read messages',
                          value: _settings!.readReceiptsEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings!.copyWith(readReceiptsEnabled: value),
                            );
                          },
                        ),
                        const Divider(color: kMediumGrey, height: 1),
                        _buildSwitchTile(
                          icon: Icons.keyboard,
                          title: 'Typing Indicators',
                          subtitle: 'Show when you\'re typing',
                          value: _settings!.typingIndicatorsEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings!.copyWith(
                                typingIndicatorsEnabled: value,
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Appearance Section
                    _buildSection(
                      title: 'Appearance',
                      children: [
                        _buildActionTile(
                          icon: Icons.wallpaper_outlined,
                          title: 'Chat Wallpaper',
                          subtitle: _settings!.customWallpaper ?? 'Default',
                          onTap: _selectWallpaper,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Advanced Section
                    _buildSection(
                      title: 'Advanced',
                      children: [
                        _buildSwitchTile(
                          icon: Icons.timer_outlined,
                          title: 'Disappearing Messages',
                          subtitle: 'Messages auto-delete after a set time',
                          value: _settings!.disappearingMessagesEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings!.copyWith(
                                disappearingMessagesEnabled: value,
                              ),
                            );
                          },
                        ),
                        const Divider(color: kMediumGrey, height: 1),
                        _buildActionTile(
                          icon: Icons.file_download_outlined,
                          title: 'Export Chat',
                          subtitle: 'Save chat history as text file',
                          onTap: _exportChat,
                        ),
                      ],
                    ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Text(
            title,
            style: GoogleFonts.inter(
              color: kLimeGreen,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: kDarkerGrey,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      secondary: Icon(icon, color: kLimeGreen, size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: kLimeGreen,
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon, color: kLimeGreen, size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right, color: kLightGrey, size: 18),
      onTap: onTap,
    );
  }

  void _selectWallpaper() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kDarkerGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Wallpaper',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.wallpaper,
                  color: kLimeGreen,
                  size: 20,
                ),
                title: Text(
                  'Default',
                  style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _updateSettings(_settings!.copyWith(customWallpaper: null));
                },
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.photo_library,
                  color: kLimeGreen,
                  size: 20,
                ),
                title: Text(
                  'Choose from Gallery',
                  style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Custom wallpapers coming soon!'),
                      backgroundColor: kDarkerGrey,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportChat() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Exporting chat...'),
          backgroundColor: kDarkerGrey,
          duration: Duration(seconds: 2),
        ),
      );

      final chatText = await _directChatService.exportChat(widget.room.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${chatText.split('\n').length} lines'),
            backgroundColor: kLimeGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // TODO: Save to file or share
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(safeUserFacingText('Failed to export: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
