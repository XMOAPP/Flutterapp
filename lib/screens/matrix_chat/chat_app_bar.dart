import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../theme.dart';
import '../../services/matrix_service.dart';
import '../../services/direct_chat_service.dart';
import '../../services/voip_service.dart';
import '../../providers/matrix_provider.dart';
import '../../widgets/direct_chat/online_status_indicator.dart';
import '../../widgets/story/story_avatar.dart';
import '../group/group_info_screen.dart';
import '../channel/channel_info_screen.dart';
import '../direct_chat/saved_messages_info_screen.dart';
import '../direct_chat/user_profile_screen.dart';

/// Builds the app bar for the Matrix chat screen
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Room room;
  final VoidCallback onBack;
  final Future<void> Function() onDeleteChat;
  final Future<void> Function()? onLeaveRoom;
  final Future<void> Function()? onDeleteGroup;
  final Future<void> Function() onArchiveChat;
  final MatrixProvider? matrixProvider;
  final VoidCallback onSearch;

  const ChatAppBar({
    super.key,
    required this.room,
    required this.onBack,
    required this.onDeleteChat,
    this.onLeaveRoom,
    this.onDeleteGroup,
    required this.onArchiveChat,
    this.matrixProvider,
    required this.onSearch,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  bool get _isAdmin => room.ownPowerLevel >= 50;
  bool get _isChannel => room.isChannel;
  bool get _isDirect => MatrixService().isDirectRoom(room);
  bool get _isSavedMessages => MatrixService().isSavedMessagesRoom(room);
  bool get _supportsCalls => !_isSavedMessages && (_isDirect || !_isChannel);

  Future<void> _openGroupInfo(BuildContext context) async {
    if (_isSavedMessages) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SavedMessagesInfoScreen(room: room),
        ),
      );
      return;
    }
    if (_isChannel) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChannelInfoScreen(room: room),
        ),
      );
    } else {
      final result = await Navigator.push<GroupInfoResult>(
        context,
        MaterialPageRoute(
          builder: (_) => GroupInfoScreen(room: room),
        ),
      );
      if (result == GroupInfoResult.searchMessages && context.mounted) {
        onSearch();
      }
    }
  }

  Future<void> _openUserProfile(BuildContext context) async {
    // Get the other user's ID in direct chat
    final otherUserId = MatrixService().getDirectPeerUserId(room);
    if (otherUserId == null) return;

    final shouldArchive = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          room: room,
          userId: otherUserId,
        ),
      ),
    );
    if (shouldArchive == true && context.mounted) {
      await onArchiveChat();
    }
  }

  Future<void> _startRoomCall(BuildContext context, bool video) async {
    try {
      await VoipService().startCall(room, video: video);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Unable to start ${video ? 'video' : 'voice'} call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrixService = MatrixService();
    final memberCount = room.summary.mJoinedMemberCount ?? 0;
    final audienceLabel = _isSavedMessages
        ? ''
        : _isChannel
            ? 'subscribers'
            : 'members';
    final name = MatrixService.cleanName(
      _isSavedMessages
          ? 'Saved Messages'
          : matrixService.getResolvedDisplayName(room),
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
                    fallbackIcon: _isSavedMessages
                        ? Icons.bookmark
                        : _isChannel
                            ? Icons.campaign
                            : Icons.group,
                    fallbackIconSize: _isSavedMessages ? 21 : null,
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
                        if (!_isSavedMessages)
                          Text(
                            '$memberCount $audienceLabel',
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
        if (_supportsCalls)
          ValueListenableBuilder<int>(
            valueListenable: VoipService().callStateVersion,
            builder: (context, _, __) {
              final blocked = VoipService().isCallStartBlocked(room);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: blocked ? 'Call unavailable' : 'Voice call',
                    icon: Icon(
                      blocked ? Icons.phone_disabled : Icons.call,
                      color: kWhite,
                      size: 21,
                    ),
                    onPressed:
                        blocked ? null : () => _startRoomCall(context, false),
                  ),
                  IconButton(
                    tooltip: blocked ? 'Call unavailable' : 'Video call',
                    icon: Icon(
                      blocked ? Icons.videocam_off : Icons.videocam,
                      color: kWhite,
                      size: 23,
                    ),
                    onPressed:
                        blocked ? null : () => _startRoomCall(context, true),
                  ),
                ],
              );
            },
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: kWhite, size: 28),
          color: const Color(0xFF262728),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onSelected: (value) => _handleMenuAction(context, value),
          itemBuilder: (context) => _buildMenuItems(),
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final items = <PopupMenuEntry<String>>[];

    if (_isSavedMessages) {
      items.add(_buildMenuItem(
        'saved_info',
        Icons.photo_library,
        'Shared Media',
        kWhite,
      ));
    } else if (_isDirect) {
      final muted = room.pushRuleState == PushRuleState.dontNotify;
      items.add(_buildMenuItem(
        'search',
        Icons.search,
        'Search',
        kWhite,
      ));
      items.add(_buildMenuItem(
        'mute',
        muted
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        muted ? 'Unmute' : 'Mute',
        kWhite,
      ));
      items.add(_buildMenuItem(
        'archive',
        Icons.archive_outlined,
        'Archive Chat',
        kWhite,
      ));
      items.add(_buildMenuItem(
        'delete_chat',
        Icons.delete_outline,
        'Delete Chat',
        Colors.redAccent,
      ));
    } else {
      final muted = room.pushRuleState == PushRuleState.dontNotify;
      items.add(_buildMenuItem(
        'search',
        Icons.search,
        'Search',
        kWhite,
      ));
      items.add(_buildMenuItem(
        'mute',
        muted
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        muted ? 'Unmute' : 'Mute',
        kWhite,
      ));
      items.add(_buildMenuItem(
        'archive',
        Icons.archive_outlined,
        _isChannel ? 'Archive Channel' : 'Archive Group',
        kWhite,
      ));

      if (_isAdmin) {
        items.add(_buildMenuItem(
          'delete_group',
          Icons.delete_forever,
          _isChannel ? 'Delete Channel' : 'Delete Group',
          Colors.redAccent,
        ));
      } else {
        items.add(_buildMenuItem(
          'leave',
          Icons.exit_to_app,
          _isChannel ? 'Leave Channel' : 'Leave Group',
          Colors.orange,
        ));
      }
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
          Text(
            label,
            style: GoogleFonts.inter(color: color, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, String action) async {
    switch (action) {
      case 'search':
        onSearch();
        break;

      case 'mute':
        await _toggleRoomMute(context);
        break;

      case 'archive':
        await onArchiveChat();
        break;

      case 'saved_info':
        _openGroupInfo(context);
        break;

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
                ? 'This will permanently delete the channel for all subscribers. This action cannot be undone.'
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

  Future<void> _toggleRoomMute(BuildContext context) async {
    final shouldMute = room.pushRuleState != PushRuleState.dontNotify;

    try {
      final directChatService = DirectChatService(
        matrixProvider?.service ?? MatrixService(),
      );
      await directChatService.toggleMute(room.id, shouldMute);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shouldMute ? 'Chat muted' : 'Chat unmuted'),
          backgroundColor: kLimeGreen,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update mute: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
  String? _avatarUrl;

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
      final peer = widget.room.getParticipants().where(
            (user) => user.id == otherUserId,
          );
      final avatarUrl = peer.isEmpty ? null : peer.first.avatarUrl?.toString();

      if (mounted) {
        setState(() {
          _isOnline = isOnline;
          _lastSeen = lastSeen;
          _avatarUrl = avatarUrl;
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
              StoryAvatar(
                userName: widget.name,
                avatarUrl: _avatarUrl,
                size: 36,
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
