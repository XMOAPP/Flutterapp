import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../providers/matrix_provider.dart';
import '../../services/call_history_service.dart';
import '../../services/matrix_service.dart';
import '../../theme.dart';
import '../../widgets/story/story_avatar.dart';
import '../matrix_chat_screen.dart';

enum _CallsFilter { all, missed, rejected, outgoing, incoming }

class CallsView extends StatefulWidget {
  const CallsView({super.key});

  @override
  State<CallsView> createState() => _CallsViewState();
}

class _CallsViewState extends State<CallsView> {
  _CallsFilter _filter = _CallsFilter.all;

  @override
  void initState() {
    super.initState();
    CallHistoryService().ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CallHistoryEntry>>(
      valueListenable: CallHistoryService().entries,
      builder: (context, entries, _) {
        final filtered = _filtered(entries);

        return Column(
          children: [
            _buildFilters(entries),
            Expanded(
              child: filtered.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _CallHistoryTile(entry: filtered[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  List<CallHistoryEntry> _filtered(List<CallHistoryEntry> entries) {
    return switch (_filter) {
      _CallsFilter.all => entries,
      _CallsFilter.missed => entries.where((entry) => entry.isMissed).toList(),
      _CallsFilter.rejected =>
        entries.where((entry) => entry.isRejected).toList(),
      _CallsFilter.outgoing =>
        entries.where((entry) => entry.isOutgoing).toList(),
      _CallsFilter.incoming =>
        entries.where((entry) => entry.isIncoming).toList(),
    };
  }

  Widget _buildFilters(List<CallHistoryEntry> entries) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_filterLabel(_filter)} Calls',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          PopupMenuButton<_CallsFilter>(
            color: const Color(0xFF262728),
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            icon: const Icon(Icons.more_vert, color: kWhite, size: 24),
            onSelected: (filter) => setState(() => _filter = filter),
            itemBuilder: (context) => [
              _filterMenuItem('All', _CallsFilter.all, entries.length),
              _filterMenuItem(
                'Missed',
                _CallsFilter.missed,
                entries.where((entry) => entry.isMissed).length,
              ),
              _filterMenuItem(
                'Rejected',
                _CallsFilter.rejected,
                entries.where((entry) => entry.isRejected).length,
              ),
              _filterMenuItem(
                'Outgoing',
                _CallsFilter.outgoing,
                entries.where((entry) => entry.isOutgoing).length,
              ),
              _filterMenuItem(
                'Incoming',
                _CallsFilter.incoming,
                entries.where((entry) => entry.isIncoming).length,
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_CallsFilter> _filterMenuItem(
    String label,
    _CallsFilter filter,
    int count,
  ) {
    final selected = _filter == filter;
    return PopupMenuItem<_CallsFilter>(
      value: filter,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? kLimeGreen : kLightGrey,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            count.toString(),
            style: GoogleFonts.inter(
              color: selected ? kLimeGreen : kLightGrey,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(_CallsFilter filter) {
    return switch (filter) {
      _CallsFilter.all => 'All',
      _CallsFilter.missed => 'Missed',
      _CallsFilter.rejected => 'Rejected',
      _CallsFilter.outgoing => 'Outgoing',
      _CallsFilter.incoming => 'Incoming',
    };
  }

  Widget _emptyState() {
    return Center(
      child: Text(
        'No calls yet',
        style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  final CallHistoryEntry entry;

  const _CallHistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    Room? room;
    for (final candidate in context.watch<MatrixProvider>().rooms) {
      if (candidate.id == entry.roomId) {
        room = candidate;
        break;
      }
    }
    final title = room == null
        ? entry.title
        : MatrixService.cleanName(MatrixService().getResolvedDisplayName(room));
    final avatarUrl = room?.avatar?.toString() ?? entry.avatarUrl;
    final statusColor = entry.isMissed || entry.isRejected
        ? Colors.redAccent
        : entry.isOutgoing
        ? kLimeGreen
        : const Color(0xFF72B7F2);
    final icon = entry.video ? Icons.videocam : Icons.call;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: StoryAvatar(
        userName: title,
        avatarUrl: avatarUrl,
        size: 46,
        fallbackIcon: entry.kind == CallHistoryKind.group ? Icons.group : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(entry.timestamp),
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(_directionIcon(entry), color: statusColor, size: 14),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                entry.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      trailing: Icon(icon, color: kWhite, size: 28),
      onTap: () {
        if (room == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatrixChatScreen(
              room: room,
              matrixProvider: context.read<MatrixProvider>(),
            ),
          ),
        );
      },
    );
  }

  IconData _directionIcon(CallHistoryEntry entry) {
    if (entry.isMissed || entry.isRejected) return Icons.call_missed;
    return entry.isOutgoing ? Icons.call_made : Icons.call_received;
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final callDay = DateTime(date.year, date.month, date.day);
    if (callDay == today) {
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final suffix = date.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $suffix';
    }
    if (today.difference(callDay).inDays == 1) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }
}
