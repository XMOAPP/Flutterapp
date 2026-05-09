import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/chat_filter_provider.dart';
import '../providers/matrix_provider.dart';
import '../services/app_settings_service.dart';
import '../services/matrix_service.dart';
import 'home/new_chat_fab.dart';
import 'home/category_filters.dart';
import 'home/chat_list.dart';
import 'home/stories_view.dart';
import 'home/xmo_drawer.dart';
import 'home/matrix_room_tile.dart';
import 'matrix_chat_screen.dart';

/// Main home screen with chat list and navigation
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Public room search state
  List<PublicRoomsChunk> _publicResults = [];
  final Map<String, bool> _publicRoomChannelFlags = {};
  bool _searchingPublic = false;
  String? _publicSearchError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _applyDefaultTab();
  }

  Future<void> _applyDefaultTab() async {
    final settings = await AppSettingsService().load();
    if (!mounted) return;

    final filter = switch (settings.defaultChatFilter) {
      'stories' => ChatFilter.stories,
      'groups' => ChatFilter.groups,
      'channels' => ChatFilter.channels,
      _ => ChatFilter.all,
    };
    context.read<ChatFilterProvider>().setFilter(filter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
      _publicResults = [];
      _publicRoomChannelFlags.clear();
      _publicSearchError = null;
    });
  }

  void _stopSearch() {
    _debounce?.cancel();
    setState(() {
      _isSearching = false;
      _publicResults = [];
      _publicRoomChannelFlags.clear();
      _searchingPublic = false;
      _publicSearchError = null;
    });
    _searchController.clear();
    context.read<ChatFilterProvider>().setSearchQuery('');
  }

  void _onSearchChanged(String value) {
    context.read<ChatFilterProvider>().setSearchQuery(value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _publicResults = [];
        _searchingPublic = false;
      });
      return;
    }
    setState(() => _searchingPublic = true);
    _debounce = Timer(const Duration(milliseconds: 450),
        () => _fetchPublicRooms(value.trim()));
  }

  Future<void> _fetchPublicRooms(String query) async {
    if (!mounted) return;
    setState(() {
      _publicSearchError = null;
    });
    try {
      final svc = context.read<MatrixProvider>().service;
      final results = await svc.searchPublicRooms(query);
      debugPrint('[PublicSearch] Got ${results.length} results for "$query"');
      if (mounted) {
        setState(() {
          _publicResults = results;
          _searchingPublic = false;
        });
        _resolvePublicRoomTypes(results);
      }
    } catch (e) {
      debugPrint('[PublicSearch] ERROR: $e');
      if (mounted) {
        setState(() {
          _searchingPublic = false;
          _publicSearchError = e.toString();
        });
      }
    }
  }

  Future<void> _resolvePublicRoomTypes(List<PublicRoomsChunk> rooms) async {
    final provider = context.read<MatrixProvider>();
    for (final room in rooms) {
      if (_publicRoomChannelFlags.containsKey(room.roomId)) continue;
      final isChannel = await provider.service.isPublicRoomChannel(
        room.roomId,
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() => _publicRoomChannelFlags[room.roomId] = isChannel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      drawer: const XmoDrawer(),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (!_isSearching) const CategoryFilters(),
          if (!_isSearching) const SizedBox(height: 4),
          Expanded(
            child: _isSearching && _searchController.text.isNotEmpty
                ? _buildCombinedResults()
                : Consumer<ChatFilterProvider>(
                    builder: (context, filterProvider, _) {
                      // Show Stories view when Stories tab is selected
                      if (filterProvider.filter == ChatFilter.stories) {
                        return const StoriesView();
                      }
                      // Show regular chat list for other tabs
                      return const ChatList();
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: const NewChatFAB(),
    );
  }

  /// Shows joined-room matches + public channel results together
  Widget _buildCombinedResults() {
    final rawQuery = _searchController.text.trim();
    final query = rawQuery.toLowerCase();
    final matrixProvider = context.read<MatrixProvider>();
    final matrixService = matrixProvider.service;
    final directIdentifier = MatrixService.extractRoomIdentifier(rawQuery);

    // Local matches
    final localRooms = matrixProvider.rooms.where((r) {
      final nameMatches =
          matrixService.getResolvedDisplayName(r).toLowerCase().contains(query);
      final idMatches = directIdentifier != null && r.id == directIdentifier;
      return nameMatches || idMatches;
    }).toList();

    // Public room results (exclude all already-joined rooms).
    final joinedIds = matrixProvider.rooms.map((r) => r.id).toSet();
    final publicChannels =
        _publicResults.where((c) => !joinedIds.contains(c.roomId)).toList();

    if (localRooms.isEmpty && publicChannels.isEmpty && !_searchingPublic) {
      if (_publicSearchError != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined,
                  color: Colors.white24, size: 36),
              const SizedBox(height: 12),
              Text('Could not search public channels',
                  style:
                      GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 6),
              Text(_publicSearchError!,
                  textAlign: TextAlign.center,
                  style:
                      GoogleFonts.inter(color: Colors.white24, fontSize: 10)),
            ],
          ),
        );
      }
      return Center(
        child: Text('No results for "$rawQuery"',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Local rooms ──────────────────────────────────────────────────
        if (localRooms.isNotEmpty) ...[
          _sectionHeader('Chats'),
          ...localRooms.map(
              (room) => MatrixRoomTile(key: ValueKey(room.id), room: room)),
        ],
        // ── Public groups/channels ──────────────────────────────────────────
        if (publicChannels.isNotEmpty) ...[
          _sectionHeader('Public Rooms'),
          ...publicChannels.map((chunk) => _publicChannelTile(chunk)),
        ],
        if (_searchingPublic)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(color: kLimeGreen, strokeWidth: 2),
            )),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: kLightGrey, // Changed from kMediumGrey for better visibility
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _publicChannelTile(PublicRoomsChunk chunk) {
    final name = chunk.name ?? chunk.roomId;
    final topic = chunk.topic ?? '';
    final members = chunk.numJoinedMembers;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'G';
    final provider = context.read<MatrixProvider>();
    final joinedRoom = provider.service.getRoomById(chunk.roomId);
    final isJoined = joinedRoom != null;
    final isChannel =
        joinedRoom?.isChannel ?? _publicRoomChannelFlags[chunk.roomId] ?? false;
    final roomType = isChannel ? 'Channel' : 'Group';
    final roomIcon = isChannel ? Icons.campaign : Icons.group;

    return ListTile(
      tileColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: kLimeGreen,
        child: Text(initial,
            style:
                GoogleFonts.inter(color: kBlack, fontWeight: FontWeight.bold)),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(name,
                style: GoogleFonts.inter(
                    color: kWhite, fontWeight: FontWeight.w600, fontSize: 14),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: kLimeGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(roomIcon, color: kLimeGreen, size: 9),
                const SizedBox(width: 2),
                Text(
                  roomType,
                  style: const TextStyle(
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
      subtitle: Text(
        _publicRoomSubtitle(topic, members),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
            color: kLightGrey, fontSize: 11), // Changed to kLightGrey
      ),
      trailing: null, // Removed Join button as requested
      onTap: () {
        if (isJoined) {
          final room = provider.service.getRoomById(chunk.roomId);
          if (room != null) {
            Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      MatrixChatScreen(room: room, matrixProvider: provider),
                ));
          }
        } else {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MatrixChatScreen(
                    previewChannel: chunk, matrixProvider: provider),
              ));
        }
      },
    );
  }

  String _publicRoomSubtitle(String topic, int members) {
    final memberText =
        members > 0 ? '$members members' : 'Tap to preview and join';
    return topic.isNotEmpty ? '$topic  •  $memberText' : memberText;
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: kBlack,
      elevation: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: kWhite, size: 24),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: _isSearching
          ? TextField(
              controller: _searchController,
              style: _searchTextStyle,
              decoration: InputDecoration(
                hintText: 'Search chats & channels...',
                hintStyle: _hintTextStyle,
                border: InputBorder.none,
              ),
              onChanged: _onSearchChanged,
              autofocus: true,
            )
          : Text('xmo', style: _titleTextStyle),
      centerTitle: true,
      actions: [
        IconButton(
          icon: Icon(
            _isSearching ? Icons.close : Icons.search,
            color: kWhite,
            size: 22,
          ),
          onPressed: _isSearching ? _stopSearch : _startSearch,
        ),
      ],
    );
  }

  static final _titleTextStyle = GoogleFonts.inter(
    color: kWhite,
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );

  static final _searchTextStyle =
      GoogleFonts.inter(color: kWhite, fontSize: 15);
  static final _hintTextStyle =
      GoogleFonts.inter(color: Colors.white38, fontSize: 15);
}
