import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/matrix_service.dart';
import '../../widgets/story/story_avatar.dart';
import '../matrix_chat_screen.dart';

/// Matrix room tile for displaying Matrix rooms in the chat list
class MatrixRoomTile extends StatelessWidget {
  final Room room;
  final bool showUnreadBadge;

  const MatrixRoomTile({
    super.key,
    required this.room,
    this.showUnreadBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final matrixService = MatrixService();
    final isDirect = matrixService.isDirectRoom(room);
    final isSavedMessages = matrixService.isSavedMessagesRoom(room);
    final cleanedName = isSavedMessages
        ? 'Saved Messages'
        : MatrixService.cleanName(matrixService.getResolvedDisplayName(room));
    final unreadCount = room.notificationCount;
    final lastEventTime = _formatLastEventTime(room.lastEvent?.originServerTs);

    String lastMsg = 'No messages yet';
    if (room.lastEvent != null) {
      final event = room.lastEvent!;
      if (event.type == EventTypes.Message) {
        lastMsg = event.body;
      } else if (event.type == EventTypes.Encrypted) {
        lastMsg = '🔒 Encrypted message';
      } else if (event.type == 'm.room.member') {
        lastMsg = 'Room created';
      }
    }

    final avatar = StoryAvatar(
      userName: cleanedName,
      avatarUrl: room.avatar?.toString(),
      size: 50,
      fallbackIcon: isSavedMessages
          ? Icons.bookmark
          : !isDirect && room.isChannel
              ? Icons.campaign
              : !isDirect && room.isGroup
                  ? Icons.group
                  : null,
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _showAvatarPreview(context, cleanedName),
        child: avatar,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              cleanedName,
              style: _titleStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isDirect && (room.isChannel || room.isGroup)) ...[
            const SizedBox(width: 8),
            room.isChannel ? const ChannelBadge() : const GroupBadge(),
          ],
        ],
      ),
      subtitle: Text(
        lastMsg,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unreadCount > 0 ? _unreadSubtitleStyle : _subtitleStyle,
      ),
      trailing: lastEventTime != null || (showUnreadBadge && unreadCount > 0)
          ? _RoomMeta(
              time: lastEventTime,
              unreadCount: showUnreadBadge ? unreadCount : 0,
            )
          : null,
      onTap: () async {
        final matrixProvider = context.read<MatrixProvider>();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatrixChatScreen(
              room: room,
              matrixProvider: matrixProvider,
            ),
          ),
        );
        if (context.mounted) {
          matrixProvider.refreshRooms();
        }
      },
    );
  }

  void _showAvatarPreview(BuildContext context, String name) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, _, __) {
        final matrixService = MatrixService();
        final isDirect = matrixService.isDirectRoom(room);
        final isSavedMessages = matrixService.isSavedMessagesRoom(room);
        final fallbackIcon = isSavedMessages
            ? Icons.bookmark
            : !isDirect && room.isChannel
                ? Icons.campaign
                : !isDirect && room.isGroup
                    ? Icons.group
                    : null;

        return Center(
          child: GestureDetector(
            onTap: () => Navigator.of(dialogContext).pop(),
            child: StoryAvatar(
              userName: name,
              avatarUrl: room.avatar?.toString(),
              size: 220,
              fallbackIcon: fallbackIcon,
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static final _titleStyle = GoogleFonts.inter(
    color: kWhite,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static final _subtitleStyle = GoogleFonts.inter(
    color: kLightGrey,
    fontSize: 13,
  );

  static final _unreadSubtitleStyle = GoogleFonts.inter(
    color: kWhite,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static String? _formatLastEventTime(DateTime? timestamp) {
    if (timestamp == null) return null;

    final now = DateTime.now();
    final local = timestamp.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);

    if (messageDay == today) {
      final hour = local.hour == 0
          ? 12
          : local.hour > 12
              ? local.hour - 12
              : local.hour;
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    if (messageDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }

    return '${local.day}/${local.month}/${local.year.toString().substring(2)}';
  }
}

class _RoomMeta extends StatelessWidget {
  final String? time;
  final int unreadCount;

  const _RoomMeta({
    required this.time,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (time != null)
            Text(
              time!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (unreadCount > 0) ...[
            const SizedBox(height: 6),
            _UnreadBadge(count: unreadCount),
          ],
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: kAudioBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Group badge widget
class GroupBadge extends StatelessWidget {
  const GroupBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.group, color: kLimeGreen, size: 10),
          const SizedBox(width: 2),
          Text(
            'Group',
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

/// Channel badge widget
class ChannelBadge extends StatelessWidget {
  const ChannelBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.campaign, color: kLimeGreen, size: 10),
          const SizedBox(width: 2),
          Text(
            'Channel',
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
