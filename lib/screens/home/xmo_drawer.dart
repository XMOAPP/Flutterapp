import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/matrix_service.dart';
import '../../widgets/story/story_avatar.dart';
import '../app_settings_screen.dart';
import '../login_screen.dart';
import '../profile_settings_screen.dart';

/// Main navigation drawer for the app
class XmoDrawer extends StatelessWidget {
  const XmoDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0F0F0F),
      child: SafeArea(
        child: Selector<MatrixProvider, DrawerData>(
          selector: (_, provider) => DrawerData(
            displayName: provider.displayName ?? 'Unknown',
            userId: provider.userId ?? '',
            avatarUrl: provider.avatarUrl,
          ),
          builder: (context, data, _) {
            return Column(
              children: [
                DrawerHeader(data: data),
                const Divider(color: kDarkGrey, height: 1),
                const SizedBox(height: 8),
                const CreateRoomTile(),
                ..._buildMenuItems(context),
                const Spacer(),
                const Divider(color: kDarkGrey, height: 1),
                const LogoutTile(),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context) {
    const items = [
      {'icon': Icons.person_outline, 'label': 'My Profile'},
      {'icon': Icons.contacts_outlined, 'label': 'Contacts'},
      {'icon': Icons.phone_outlined, 'label': 'Calls'},
      {'icon': Icons.bookmark_outline, 'label': 'Saved Messages'},
      {'icon': Icons.settings_outlined, 'label': 'Settings'},
      {'icon': Icons.info_outline, 'label': 'About xmo'},
    ];

    return items.map((item) {
      final label = item['label'] as String;
      return ListTile(
        leading: Icon(item['icon'] as IconData, color: kWhite, size: 22),
        title: Text(
          label,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          if (label == 'My Profile') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProfileSettingsScreen(),
              ),
            );
          } else if (label == 'Settings') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AppSettingsScreen(),
              ),
            );
          }
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      );
    }).toList();
  }
}

/// Data class for drawer
class DrawerData {
  final String displayName;
  final String userId;
  final String? avatarUrl;

  const DrawerData({
    required this.displayName,
    required this.userId,
    this.avatarUrl,
  });
}

/// Drawer header with user info
class DrawerHeader extends StatelessWidget {
  final DrawerData data;

  const DrawerHeader({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          StoryAvatar(
            userName: data.displayName,
            avatarUrl: data.avatarUrl,
            size: 44,
            backgroundColor: kLimeGreen,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.displayName,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  data.userId.contains(':')
                      ? '@${MatrixService.cleanName(data.userId)}'
                      : data.userId,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Create new Matrix room tile
class CreateRoomTile extends StatelessWidget {
  const CreateRoomTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.add_circle_outline, color: kLimeGreen, size: 22),
      title: Text(
        'New Matrix Room',
        style: GoogleFonts.inter(
          color: kLimeGreen,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: () {
        Navigator.pop(context);
        _showCreateRoomDialog(context);
      },
    );
  }

  void _showCreateRoomDialog(BuildContext context) {
    final ctrl = TextEditingController();
    final provider = context.read<MatrixProvider>();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kDarkerGrey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'New Matrix Room',
          style: GoogleFonts.inter(color: kWhite, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.inter(color: kWhite),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Room name',
            hintStyle: GoogleFonts.inter(color: kLightGrey),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kDarkGrey),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kLimeGreen),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              await provider.createRoom(ctrl.text.trim());
            },
            child: Text(
              'Create',
              style: GoogleFonts.inter(
                color: kLimeGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logout tile
class LogoutTile extends StatelessWidget {
  const LogoutTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.logout, color: Colors.red[400], size: 22),
      title: Text(
        'Logout',
        style: GoogleFonts.inter(
          color: Colors.red[400],
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: () async {
        final provider = context.read<MatrixProvider>();
        Navigator.pop(context);
        await provider.logout();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      },
    );
  }
}
