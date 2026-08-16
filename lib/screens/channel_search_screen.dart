import 'package:xmo/utils/user_facing_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../theme.dart';
import '../widgets/story/story_avatar.dart';
import 'matrix_chat_screen.dart';

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// GLOBAL CHANNEL SEARCH SCREEN
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

class ChannelSearchScreen extends StatefulWidget {
  final String initialQuery;
  const ChannelSearchScreen({super.key, this.initialQuery = ''});

  @override
  State<ChannelSearchScreen> createState() => _ChannelSearchScreenState();
}

class _ChannelSearchScreenState extends State<ChannelSearchScreen> {
  final _searchCtrl = TextEditingController();
  List<PublicRoomsChunk> _results = [];
  final Map<String, bool> _roomChannelFlags = {};
  bool _searching = false;
  String? _error;
  Timer? _debounce;
  int _searchRequestId = 0;
  int _roomTypeRequestId = 0;
  final Set<String> _joiningRoomIds = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initialQuery;
    _search(widget.initialQuery);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query.trim()),
    );
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    final requestId = ++_searchRequestId;
    _roomTypeRequestId++;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final svc = context.read<MatrixProvider>().service;
      final results = await svc.searchPublicRooms(query);
      if (!mounted || requestId != _searchRequestId) return;
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
        });
        _resolveRoomTypes(results);
      }
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      if (mounted) {
        setState(() {
          _error = userFacingError(
            e,
            fallback: 'Could not complete this action.',
          );
          _searching = false;
        });
      }
    }
  }

  Future<void> _joinRoom(PublicRoomsChunk room) async {
    final roomId = room.roomId;
    setState(() => _joiningRoomIds.add(roomId));

    final provider = context.read<MatrixProvider>();
    try {
      await provider.service.isPublicRoomChannel(roomId, forceRefresh: true);
      await provider.service.joinRoom(roomId);
      await Future.delayed(const Duration(milliseconds: 600));
      await provider.service.client.oneShotSync();
      provider.refreshRooms();

      if (!mounted) return;
      setState(() => _joiningRoomIds.remove(roomId));

      final joined = provider.service.getJoinedRoomById(roomId);
      if (joined != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MatrixChatScreen(room: joined, matrixProvider: provider),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _joiningRoomIds.remove(roomId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(safeUserFacingText('Failed to join: $e')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _resolveRoomTypes(List<PublicRoomsChunk> rooms) async {
    final provider = context.read<MatrixProvider>();
    final requestId = ++_roomTypeRequestId;
    for (final room in rooms) {
      if (_roomChannelFlags.containsKey(room.roomId)) continue;
      final isChannel = await provider.service.isPublicRoomChannel(
        room.roomId,
        forceRefresh: true,
      );
      if (!mounted || requestId != _roomTypeRequestId) return;
      setState(() => _roomChannelFlags[room.roomId] = isChannel);
    }
  }

  bool _isJoined(String roomId) {
    final svc = context.read<MatrixProvider>().service;
    return svc.getJoinedRoomById(roomId) != null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kDarkerGrey,
        elevation: 0,
        toolbarHeight: 46,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: GoogleFonts.inter(color: kWhite, fontSize: 13),
          cursorColor: kLimeGreen,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search public channelsÃ¢â‚¬Â¦',
            hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: Colors.white38,
                      size: 18,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      _search('');
                    },
                  )
                : null,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(color: kLimeGreen));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: GoogleFonts.inter(color: Colors.red, fontSize: 13),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign_outlined, color: kMediumGrey, size: 56),
            const SizedBox(height: 16),
            Text(
              'No public channels found',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: GoogleFonts.inter(color: kMediumGrey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) =>
          Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
      itemBuilder: (context, i) {
        final room = _results[i];
        final isJoined = _isJoined(room.roomId);
        final isJoining = _joiningRoomIds.contains(room.roomId);
        final isChannel = _roomChannelFlags[room.roomId] ?? false;
        final name = room.name ?? room.roomId;
        final topic = room.topic ?? '';
        final memberCount = room.numJoinedMembers;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: StoryAvatar(
            userName: name,
            avatarUrl: room.avatarUrl?.toString(),
            size: 40,
            fallbackIcon: isChannel ? Icons.campaign : Icons.groups,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kLimeGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isChannel ? Icons.campaign : Icons.group,
                      color: kLimeGreen,
                      size: 9,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      isChannel ? 'Channel' : 'Group',
                      style: GoogleFonts.inter(
                        color: kLimeGreen,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (topic.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    color: kMediumGrey,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$memberCount member${memberCount == 1 ? '' : 's'}',
                    style: GoogleFonts.inter(color: kMediumGrey, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          trailing: isJoining
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: kLimeGreen,
                    strokeWidth: 2,
                  ),
                )
              : isJoined
              ? TextButton(
                  onPressed: () {
                    final provider = context.read<MatrixProvider>();
                    final joined = provider.service.getJoinedRoomById(
                      room.roomId,
                    );
                    if (joined != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MatrixChatScreen(
                            room: joined,
                            matrixProvider: provider,
                          ),
                        ),
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: kDarkGrey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Open',
                    style: GoogleFonts.inter(
                      color: kLimeGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: () => _joinRoom(room),
                  style: TextButton.styleFrom(
                    backgroundColor: kLimeGreen,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Join',
                    style: GoogleFonts.inter(
                      color: kBlack,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
          onTap: isJoined ? null : () => _joinRoom(room),
        );
      },
    );
  }
}
