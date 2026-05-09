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
    final cleanedName =
        MatrixService.cleanName(matrixService.getResolvedDisplayName(room));
    final unreadCount = room.notificationCount;

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

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: StoryAvatar(
        userName: cleanedName,
        avatarUrl: room.avatar?.toString(),
        size: 50,
        fallbackIcon: !isDirect && room.isChannel
            ? Icons.campaign
            : !isDirect && room.isGroup
                ? Icons.group
                : null,
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
      trailing: showUnreadBadge && unreadCount > 0
          ? _UnreadBadge(count: unreadCount)
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
        color: const Color(0xFF6F8293),
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
        color: kLimeGreen.withValues(alpha: 0.15),
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
