// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/chat_filter_provider.dart';
import '../../providers/matrix_provider.dart';
import '../../models/group_models.dart';
import '../../services/group_service.dart';
import '../../services/matrix_service.dart';
import '../../widgets/story/story_avatar.dart';
import '../app_settings_screen.dart';
import '../auth_choice_screen.dart';
import '../donation_screen.dart';
import '../matrix_chat_screen.dart';
import '../profile_settings_screen.dart';

const Color _drawerBodyColor = Color(0xFF262728);
const Color _drawerHeaderColor = Color(0xFF303133);

/// Main navigation drawer for the app
class XmoDrawer extends StatelessWidget {
  const XmoDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _drawerBodyColor,
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
              const Divider(color: _drawerBodyColor, height: 1),
              const SizedBox(height: 8),
              const NewChannelTile(),
              const NewGroupTile(),
              ..._buildMenuItems(context),
              const Spacer(),
              const Divider(color: _drawerHeaderColor, height: 1),
              const LogoutTile(),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context) {
    const items = [
      {'icon': Icons.person, 'label': 'My Profile'},
      {'icon': Icons.contacts, 'label': 'Contacts'},
      {'icon': Icons.phone, 'label': 'Calls'},
      {'icon': Icons.bookmark, 'label': 'Saved Messages'},
      {'icon': Icons.settings, 'label': 'Settings'},
      {'icon': Icons.volunteer_activism, 'label': 'Donation'},
    ];

    return items.map((item) {
      final label = item['label'] as String;
      Widget leadingWidget;
      Widget titleWidget;

      if (label == 'Donation') {
        leadingWidget = SizedBox(
          width: 22,
          height: 22,
          child: OverflowBox(
            maxWidth: 100, // Let the image grow outside the 22x22 box
            maxHeight: 100,
            child: Image.asset(
              'assets/images/no_bg_transparent(1).gif',
              width: 60, // Sweet spot between 46 and 80
              height: 60,
              fit: BoxFit.contain,
            ),
          ),
        );
        titleWidget = ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Color(0xFF20D7A3), // Teal on the left
              Color(0xFF1686D9), // Blue on the right
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      } else {
        leadingWidget = Icon(item['icon'] as IconData, color: kWhite, size: 22);
        titleWidget = Text(
          label,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        );
      }

      return ListTile(
        leading: leadingWidget,
        title: titleWidget,
        onTap: () {
          if (label == 'Saved Messages') {
            _openSavedMessages(context);
            return;
          }
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
          } else if (label == 'Donation') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DonationScreen(),
              ),
            );
          } else if (label == 'Calls') {
            context.read<ChatFilterProvider>().setFilter(ChatFilter.calls);
          }
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      );
    }).toList();
  }

  Future<void> _openSavedMessages(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<MatrixProvider>();
    navigator.pop();
    try {
      final room = await provider.getOrCreateSavedMessagesRoom();
      unawaited(provider.deleteDuplicateSavedMessagesRooms());
      navigator.push(
        MaterialPageRoute(
          builder: (_) => MatrixChatScreen(
            room: room,
            matrixProvider: provider,
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Unable to open Saved Messages: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
    return Container(
      color: _drawerHeaderColor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.paddingOf(context).top + 20,
          20,
          16,
        ),
        child: Row(
          children: [
            StoryAvatar(
              userName: data.displayName,
              avatarUrl: data.avatarUrl,
              size: 44,
              backgroundColor: const Color(0xFF2C2C2E),
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
      ),
    );
  }
}

class NewGroupTile extends StatelessWidget {
  const NewGroupTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.group_add, color: kLimeGreen, size: 22),
      title: Text(
        'New Group',
        style: GoogleFonts.inter(
          color: kLimeGreen,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: () {
        final rootContext = Navigator.of(context).context;
        Navigator.pop(context);
        Future.microtask(() => _showCreateGroupDialog(rootContext));
      },
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    GroupType groupType = GroupType.private;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kDarkerGrey,
          title: Text('New Group', style: GoogleFonts.inter(color: kWhite)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: kWhite),
                decoration: _creationFieldDecoration(
                  labelText: 'Group Name',
                  hintText: 'Enter group name',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: kWhite),
                decoration: _creationFieldDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'What is this group about?',
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 20),
              Text('Group Type',
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 12)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<GroupType>(
                      title: const Text('Private (encrypted)',
                          style: TextStyle(color: kWhite, fontSize: 14)),
                      value: GroupType.private,
                      groupValue: groupType,
                      activeColor: kLimeGreen,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => groupType = value!);
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<GroupType>(
                      title: const Text('Public (not encrypted)',
                          style: TextStyle(color: kWhite, fontSize: 14)),
                      value: GroupType.public,
                      groupValue: groupType,
                      activeColor: kLimeGreen,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => groupType = value!);
                      },
                    ),
                  ),
                ],
              ),
              Text(
                'This choice cannot be changed later.',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                final provider = context.read<MatrixProvider>();
                final groupService = GroupService(provider.service);
                await _createAndOpenRoom(
                  context: context,
                  provider: provider,
                  createRoom: () => groupService.createGroup(
                    name: name,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    type: groupType,
                    joinRule: groupType == GroupType.public
                        ? JoinRule.open
                        : JoinRule.invite,
                  ),
                  errorPrefix: 'Failed to create group',
                );
              },
              child: const Text('Create', style: TextStyle(color: kLimeGreen)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _createAndOpenRoom({
  required BuildContext context,
  required MatrixProvider provider,
  required Future<String> Function() createRoom,
  required String errorPrefix,
}) async {
  BuildContext? loaderContext;
  showDialog(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (dialogContext) {
      loaderContext = dialogContext;
      return const Center(
        child: CircularProgressIndicator(color: kLimeGreen),
      );
    },
  );

  void closeLoader() {
    final dialogContext = loaderContext;
    if (dialogContext == null) return;
    loaderContext = null;
    Navigator.of(dialogContext, rootNavigator: true).pop();
  }

  try {
    final roomId = await createRoom();
    final room = await _waitForCreatedRoom(provider, roomId);
    provider.refreshRooms();

    closeLoader();
    if (!context.mounted) return;

    if (room != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MatrixChatScreen(
            room: room,
            matrixProvider: provider,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Created successfully. It will appear on Home shortly.'),
        backgroundColor: kLimeGreen,
      ),
    );
  } catch (e) {
    closeLoader();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$errorPrefix: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<Room?> _waitForCreatedRoom(
  MatrixProvider provider,
  String roomId,
) async {
  for (final delay in const [
    Duration.zero,
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(milliseconds: 900),
    Duration(milliseconds: 1400),
  ]) {
    if (delay != Duration.zero) {
      await Future.delayed(delay);
    }

    final room = _createdRoomById(provider, roomId);
    if (room != null) return room;

    try {
      await provider.service.client.oneShotSync();
    } catch (e) {
      debugPrint('[DrawerCreate] oneShotSync failed for $roomId: $e');
    }
  }

  return _createdRoomById(provider, roomId);
}

Room? _createdRoomById(MatrixProvider provider, String roomId) {
  final serviceRoom = provider.service.getRoomById(roomId);
  if (serviceRoom != null) return serviceRoom;

  for (final room in provider.rooms) {
    if (room.id == roomId) return room;
  }

  return null;
}

class NewChannelTile extends StatelessWidget {
  const NewChannelTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.campaign, color: kLimeGreen, size: 22),
      title: Text(
        'New Channel',
        style: GoogleFonts.inter(
          color: kLimeGreen,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: () {
        final rootContext = Navigator.of(context).context;
        Navigator.pop(context);
        Future.microtask(() => _showCreateChannelDialog(rootContext));
      },
    );
  }

  void _showCreateChannelDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var isPublic = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kDarkerGrey,
          title: Text('New Channel', style: GoogleFonts.inter(color: kWhite)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: kWhite),
                decoration: _creationFieldDecoration(
                  labelText: 'Channel Name',
                  hintText: 'Enter channel name',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: kWhite),
                decoration: _creationFieldDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'What is this channel about?',
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 16),
              RadioListTile<bool>(
                value: true,
                groupValue: isPublic,
                activeColor: kLimeGreen,
                contentPadding: EdgeInsets.zero,
                title: const Text('Public', style: TextStyle(color: kWhite)),
                subtitle: const Text(
                  'Anyone can find and join this channel',
                  style: TextStyle(color: kLightGrey, fontSize: 12),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => isPublic = value);
                },
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: isPublic,
                activeColor: kLimeGreen,
                contentPadding: EdgeInsets.zero,
                title: const Text('Private', style: TextStyle(color: kWhite)),
                subtitle: const Text(
                  'Only invited subscribers can join',
                  style: TextStyle(color: kLightGrey, fontSize: 12),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => isPublic = value);
                },
              ),
              if (isPublic)
                const Text(
                  'Public channels are not end-to-end encrypted.',
                  style: TextStyle(color: kLightGrey, fontSize: 12),
                ),
              const SizedBox(height: 6),
              const Text(
                'This choice cannot be changed later.',
                style: TextStyle(color: kLightGrey, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                final provider = context.read<MatrixProvider>();
                await _createAndOpenRoom(
                  context: context,
                  provider: provider,
                  createRoom: () => provider.service.createChannel(
                    name: name,
                    topic: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    isPublic: isPublic,
                  ),
                  errorPrefix: 'Failed to create channel',
                );
              },
              child: const Text('Create', style: TextStyle(color: kLimeGreen)),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _creationFieldDecoration({
  required String labelText,
  required String hintText,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(24),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    labelText: labelText,
    labelStyle: const TextStyle(color: kLightGrey),
    hintText: hintText,
    hintStyle: const TextStyle(color: Colors.white54),
    isDense: true,
    filled: true,
    fillColor: const Color(0xFF2C2C2E),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: kWhite.withValues(alpha: 0.45), width: 1),
    ),
  );
}

/// Logout tile
class LogoutTile extends StatelessWidget {
  const LogoutTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.exit_to_app, color: Colors.red[400], size: 22),
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
        final navigator = Navigator.of(context, rootNavigator: true);
        Navigator.pop(context);
        await provider.logout();
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthChoiceScreen()),
          (route) => false,
        );
      },
    );
  }
}
