import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../theme.dart';
import '../../services/matrix_service.dart';
import '../../services/direct_chat_service.dart';
import '../../providers/matrix_provider.dart';
import '../../widgets/direct_chat/online_status_indicator.dart';
import '../../widgets/story/story_avatar.dart';
import '../group/group_info_screen.dart';
import '../channel/channel_info_screen.dart';
import '../direct_chat/user_profile_screen.dart';

/// Builds the app bar for the Matrix chat screen
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Room room;
  final VoidCallback onBack;
  final Future<void> Function() onDeleteChat;
  final Future<void> Function()? onLeaveRoom;
  final Future<void> Function()? onDeleteGroup;
  final MatrixProvider? matrixProvider;

  const ChatAppBar({
    super.key,
    required this.room,
    required this.onBack,
    required this.onDeleteChat,
    this.onLeaveRoom,
    this.onDeleteGroup,
    this.matrixProvider,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  bool get _isAdmin => room.ownPowerLevel >= 50;
  bool get _isChannel => room.isChannel;
  bool get _isDirect => MatrixService().isDirectRoom(room);

  void _openGroupInfo(BuildContext context) {
    if (_isChannel) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChannelInfoScreen(room: room),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupInfoScreen(room: room),
        ),
      );
    }
  }

  void _openUserProfile(BuildContext context) {
    // Get the other user's ID in direct chat
    final otherUserId = MatrixService().getDirectPeerUserId(room);
    if (otherUserId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          room: room,
          userId: otherUserId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matrixService = MatrixService();
    final memberCount = room.summary.mJoinedMemberCount ?? 0;
    final name = MatrixService.cleanName(
      matrixService.getResolvedDisplayName(room),
    );

    return AppBar(
      backgroundColor: kBlack,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: kWhite),
        onPressed: onBack,
      ),
      titleSpacing: 0,
      title: _isDirect
          ? _DirectChatTitle(
              room: room,
              name: name,
              onTap: () => _openUserProfile(context),
              matrixProvider: matrixProvider,
            )
          : GestureDetector(
              onTap: () => _openGroupInfo(context),
              child: Row(
                children: [
                  StoryAvatar(
                    userName: name,
                    avatarUrl: room.avatar?.toString(),
                    size: 36,
                    fallbackIcon: _isChannel ? Icons.campaign : Icons.group,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.inter(
                            color: kWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$memberCount members',
                          style: GoogleFonts.inter(
                              color: kLightGrey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: kWhite, size: 22),
          color: kDarkerGrey,
          onSelected: (value) => _handleMenuAction(context, value),
          itemBuilder: (context) => _buildMenuItems(),
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final items = <PopupMenuEntry<String>>[];

    if (_isDirect) {
      // Direct chat: Only delete chat
      items.add(_buildMenuItem(
        'delete_chat',
        Icons.delete_outline,
        'Delete Chat',
        Colors.red,
      ));
    } else if (_isAdmin) {
      // Admin in group/channel: Delete chat + Delete group/channel
      items.add(_buildMenuItem(
        'delete_chat',
        Icons.delete_outline,
        'Delete Chat',
        Colors.red,
      ));
      items.add(const PopupMenuDivider());
      items.add(_buildMenuItem(
        'delete_group',
        Icons.delete_forever,
        _isChannel ? 'Delete Channel' : 'Delete Group',
        Colors.red,
      ));
    } else {
      // Regular member: Leave group/channel
      items.add(_buildMenuItem(
        'leave',
        Icons.exit_to_app,
        _isChannel ? 'Leave Channel' : 'Leave Group',
        Colors.orange,
      ));
    }

    return items;
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, String action) async {
    switch (action) {
      case 'delete_chat':
        await _confirmAndExecute(
          context,
          title: 'Delete Chat?',
          message:
              'Are you sure you want to delete this chat? This action cannot be undone.',
          confirmText: 'Delete',
          onConfirm: onDeleteChat,
        );
        break;

      case 'delete_group':
        if (onDeleteGroup != null) {
          await _confirmAndExecute(
            context,
            title: _isChannel ? 'Delete Channel?' : 'Delete Group?',
            message: _isChannel
                ? 'This will permanently delete the channel for all members. This action cannot be undone.'
                : 'This will permanently delete the group for all members. This action cannot be undone.',
            confirmText: 'Delete',
            onConfirm: onDeleteGroup!,
          );
        }
        break;

      case 'leave':
        if (onLeaveRoom != null) {
          await _confirmAndExecute(
            context,
            title: _isChannel ? 'Leave Channel?' : 'Leave Group?',
            message: _isChannel
                ? 'Are you sure you want to leave this channel?'
                : 'Are you sure you want to leave this group?',
            confirmText: 'Leave',
            onConfirm: onLeaveRoom!,
          );
        }
        break;
    }
  }

  Future<void> _confirmAndExecute(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    required Future<void> Function() onConfirm,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: kWhite,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: kLightGrey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmText,
              style: GoogleFonts.inter(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await onConfirm();
    }
  }
}

/// Direct Chat Title with Online Status
class _DirectChatTitle extends StatefulWidget {
  final Room room;
  final String name;
  final VoidCallback onTap;
  final MatrixProvider? matrixProvider;

  const _DirectChatTitle({
    required this.room,
    required this.name,
    required this.onTap,
    this.matrixProvider,
  });

  @override
  State<_DirectChatTitle> createState() => _DirectChatTitleState();
}

class _DirectChatTitleState extends State<_DirectChatTitle> {
  bool _isOnline = false;
  DateTime? _lastSeen;

  @override
  void initState() {
    super.initState();
    _loadOnlineStatus();
  }

  Future<void> _loadOnlineStatus() async {
    if (widget.matrixProvider == null) return;

    final otherUserId = widget.room.directChatMatrixID;
    if (otherUserId == null) return;

    try {
      final directChatService =
          DirectChatService(widget.matrixProvider!.service);
      final isOnline = await directChatService.isUserOnline(otherUserId);
      final lastSeen = await directChatService.getLastSeen(otherUserId);

      if (mounted) {
        setState(() {
          _isOnline = isOnline;
          _lastSeen = lastSeen;
        });
      }
    } catch (e) {
      debugPrint('[ChatAppBar] Failed to load online status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: kLimeGreen,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(
                      color: kBlack,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: OnlineStatusIndicator(
                  isOnline: _isOnline,
                  lastSeen: _lastSeen,
                  size: 9,
                ),
              ),
            ],
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                OnlineStatusIndicator(
                  isOnline: _isOnline,
                  lastSeen: _lastSeen,
                  showText: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
