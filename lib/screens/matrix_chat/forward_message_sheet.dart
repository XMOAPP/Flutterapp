import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../providers/matrix_provider.dart';
import '../../services/matrix_service.dart';
import '../../theme.dart';
import '../../widgets/story/story_avatar.dart';

Future<List<Room>?> showForwardMessageSheet({
  required BuildContext context,
  required List<Room> rooms,
  required Room currentRoom,
}) {
  final matrixService = MatrixService();
  final eligibleRooms = rooms.where((room) {
    return room.membership == Membership.join &&
        room.canSendEvent(EventTypes.Message);
  }).toList()
    ..sort((a, b) {
      final aTime = a.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      final bTime = b.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

  return showModalBottomSheet<List<Room>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kBlack,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ForwardMessageSheet(
      rooms: eligibleRooms,
      currentRoom: currentRoom,
      matrixService: matrixService,
    ),
  );
}

class _ForwardMessageSheet extends StatefulWidget {
  final List<Room> rooms;
  final Room currentRoom;
  final MatrixService matrixService;

  const _ForwardMessageSheet({
    required this.rooms,
    required this.currentRoom,
    required this.matrixService,
  });

  @override
  State<_ForwardMessageSheet> createState() => _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends State<_ForwardMessageSheet> {
  final Set<String> _selectedRoomIds = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filteredRooms = widget.rooms.where((room) {
      final name = widget.matrixService.getResolvedDisplayName(room);
      return name.toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Forward to',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: kWhite),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  hintStyle: GoogleFonts.inter(color: kLightGrey),
                  prefixIcon:
                      const Icon(Icons.search, color: kLightGrey, size: 21),
                  filled: true,
                  fillColor: kDarkerGrey,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filteredRooms.isEmpty
                  ? Center(
                      child: Text(
                        'No chats available',
                        style: GoogleFonts.inter(
                          color: kLightGrey,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredRooms.length,
                      itemBuilder: (context, index) {
                        final room = filteredRooms[index];
                        final selected = _selectedRoomIds.contains(room.id);
                        return _ForwardRoomTile(
                          room: room,
                          selected: selected,
                          isCurrentRoom: room.id == widget.currentRoom.id,
                          matrixService: widget.matrixService,
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedRoomIds.remove(room.id);
                              } else {
                                _selectedRoomIds.add(room.id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kLimeGreen,
                    foregroundColor: kBlack,
                    disabledBackgroundColor: kDarkerGrey,
                    disabledForegroundColor: kLightGrey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _selectedRoomIds.isEmpty
                      ? null
                      : () {
                          final selectedRooms = widget.rooms
                              .where(
                                  (room) => _selectedRoomIds.contains(room.id))
                              .toList();
                          Navigator.pop(context, selectedRooms);
                        },
                  icon: Transform.scale(
                    scaleX: -1,
                    child: const Icon(Icons.reply, size: 19),
                  ),
                  label: Text(
                    _selectedRoomIds.isEmpty
                        ? 'Select chat'
                        : 'Forward (${_selectedRoomIds.length})',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForwardRoomTile extends StatelessWidget {
  final Room room;
  final bool selected;
  final bool isCurrentRoom;
  final MatrixService matrixService;
  final VoidCallback onTap;

  const _ForwardRoomTile({
    required this.room,
    required this.selected,
    required this.isCurrentRoom,
    required this.matrixService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDirect = matrixService.isDirectRoom(room);
    final name = MatrixService.cleanName(
      matrixService.getResolvedDisplayName(room),
    );
    final subtitle = isCurrentRoom
        ? 'Current chat'
        : isDirect
            ? 'Direct chat'
            : room.isChannel
                ? 'Channel'
                : 'Group';

    return ListTile(
      onTap: onTap,
      leading: StoryAvatar(
        userName: name,
        avatarUrl: room.avatar?.toString(),
        size: 42,
        fallbackIcon: !isDirect && room.isChannel
            ? Icons.campaign
            : !isDirect && room.isGroup
                ? Icons.group
                : null,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
      ),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected ? kLimeGreen : kMediumGrey,
      ),
    );
  }
}
