import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../services/chat_archive_service.dart';
import '../theme.dart';
import 'home/matrix_room_tile.dart';

class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  final Set<String> _restoredRoomIds = <String>{};
  final Set<String> _restoringRoomIds = <String>{};

  Future<void> _unarchive(Room room, MatrixProvider provider) async {
    if (!_restoringRoomIds.add(room.id)) return;
    setState(() {});

    try {
      await ChatArchiveService(provider.service).unarchive(room);
      _restoredRoomIds.add(room.id);
      provider.refreshRooms();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat restored to Home'),
          backgroundColor: kLimeGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(safeUserFacingText('Unable to restore chat: $error')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _restoringRoomIds.remove(room.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        title: Text(
          'Archived Chats',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Consumer<MatrixProvider>(
        builder: (context, provider, _) {
          final archivedRooms = provider.rooms.where((room) {
            final active =
                room.membership == Membership.join ||
                room.membership == Membership.invite;
            return active &&
                ChatArchiveService.isArchived(room) &&
                !_restoredRoomIds.contains(room.id);
          }).toList();

          if (archivedRooms.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.archive_outlined,
                    color: kMediumGrey,
                    size: 46,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No archived chats',
                    style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: archivedRooms.length,
            itemBuilder: (context, index) {
              final room = archivedRooms[index];
              final restoring = _restoringRoomIds.contains(room.id);
              return MatrixRoomTile(
                key: ValueKey(room.id),
                room: room,
                showUnreadBadge: false,
                trailing: restoring
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                          color: kLimeGreen,
                          strokeWidth: 2,
                        ),
                      )
                    : IconButton(
                        tooltip: 'Unarchive',
                        icon: const Icon(
                          Icons.unarchive_outlined,
                          color: kWhite,
                        ),
                        onPressed: () => _unarchive(room, provider),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
