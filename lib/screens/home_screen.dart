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
import '../services/privacy_service.dart';
import 'home/new_chat_fab.dart';
import 'home/category_filters.dart';
import 'home/chat_list.dart';
import 'home/xmo_drawer.dart';
import 'home/matrix_room_tile.dart';
import 'auth_choice_screen.dart';
import 'matrix_chat_screen.dart';
import 'user_profile_preview_screen.dart';
import 'user_search/user_tile.dart';

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
  List<Profile> _userResults = [];
  final Map<String, bool> _publicRoomChannelFlags = {};
  bool _searchingPublic = false;
  bool _searchingUsers = false;
  String? _publicSearchError;
  Timer? _debounce;
  int _publicSearchRequestId = 0;
  int _userSearchRequestId = 0;
  int _publicRoomTypeRequestId = 0;

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
      _userResults = [];
      _publicRoomChannelFlags.clear();
      _publicSearchError = null;
    });
  }

  void _stopSearch() {
    _debounce?.cancel();
    _publicSearchRequestId++;
    _userSearchRequestId++;
    _publicRoomTypeRequestId++;
    setState(() {
      _isSearching = false;
      _publicResults = [];
      _userResults = [];
      _publicRoomChannelFlags.clear();
      _searchingPublic = false;
      _searchingUsers = false;
      _publicSearchError = null;
    });
    _searchController.clear();
    context.read<ChatFilterProvider>().setSearchQuery('');
  }

  void _onSearchChanged(String value) {
    context.read<ChatFilterProvider>().setSearchQuery(value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _publicSearchRequestId++;
      _userSearchRequestId++;
      _publicRoomTypeRequestId++;
      setState(() {
        _publicResults = [];
        _userResults = [];
        _searchingPublic = false;
        _searchingUsers = false;
      });
      return;
    }
    final searchesUsers = value.trim().startsWith('@');
    setState(() {
      _searchingPublic = !searchesUsers;
      _searchingUsers = searchesUsers;
      if (searchesUsers) {
        _publicResults = [];
        _publicRoomChannelFlags.clear();
        _publicSearchError = null;
        _publicSearchRequestId++;
        _publicRoomTypeRequestId++;
      } else {
        _userResults = [];
        _userSearchRequestId++;
      }
    });
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final query = value.trim();
      if (searchesUsers) {
        _fetchUsers(query);
      } else {
        _fetchPublicRooms(query);
      }
    });
  }

  Future<void> _fetchPublicRooms(String query) async {
    if (!mounted) return;
    final requestId = ++_publicSearchRequestId;
    setState(() {
      _publicSearchError = null;
    });
    try {
      final svc = context.read<MatrixProvider>().service;
      final results = await svc.searchPublicRooms(query);
      debugPrint('[PublicSearch] Got ${results.length} results for "$query"');
      if (!mounted || requestId != _publicSearchRequestId) return;
      if (mounted) {
        setState(() {
          _publicResults = results;
          _searchingPublic = false;
        });
        _resolvePublicRoomTypes(results);
      }
    } catch (e) {
      debugPrint('[PublicSearch] ERROR: $e');
      if (!mounted || requestId != _publicSearchRequestId) return;
      if (mounted) {
        setState(() {
          _searchingPublic = false;
          _publicSearchError = e.toString();
        });
      }
    }
  }

  Future<void> _fetchUsers(String query) async {
    if (!mounted) return;
    final requestId = ++_userSearchRequestId;
    if (!query.startsWith('@')) {
      setState(() {
        _userResults = [];
        _searchingUsers = false;
      });
      return;
    }

    try {
      final provider = context.read<MatrixProvider>();
      final privacyService = PrivacyService(provider.service);
      final publicAccounts = await privacyService.searchPublicAccounts(query);
      final explicitPrivateUserIds =
          await privacyService.searchPrivateAccountIds(query);
      final byUserId = <String, Profile>{};
      final myId = provider.userId;

      void addProfile(Profile profile) {
        final userId = profile.userId;
        if (userId == myId) return;
        if (explicitPrivateUserIds.contains(userId)) return;
        byUserId[userId] = profile;
      }

      for (final account in publicAccounts) {
        addProfile(
          Profile(
            userId: account.userId,
            displayName: account.displayName,
            avatarUrl: account.avatarUrl == null
                ? null
                : Uri.tryParse(account.avatarUrl!),
          ),
        );
      }

      for (final profile in await provider.searchUsers(query)) {
        addProfile(profile);
      }

      final exactProfile = await _lookupExactMatrixUser(provider, query);
      if (exactProfile != null) addProfile(exactProfile);

      final results = byUserId.values.toList()
        ..sort((a, b) {
          final aName = (a.displayName ?? a.userId).toLowerCase();
          final bName = (b.displayName ?? b.userId).toLowerCase();
          return aName.compareTo(bName);
        });

      if (!mounted || requestId != _userSearchRequestId) return;
      setState(() {
        _userResults = results.take(20).toList();
        _searchingUsers = false;
      });
    } catch (e) {
      debugPrint('[HomeSearch] User search failed: $e');
      if (!mounted || requestId != _userSearchRequestId) return;
      setState(() {
        _userResults = [];
        _searchingUsers = false;
      });
    }
  }

  Future<Profile?> _lookupExactMatrixUser(
    MatrixProvider provider,
    String query,
  ) async {
    final userId = _matrixUserIdFromQuery(query);
    if (userId == null) return null;

    try {
      final profile = await provider.service.client.getProfileFromUserId(
        userId,
      );
      return Profile(
        userId: userId,
        displayName: profile.displayName,
        avatarUrl: profile.avatarUrl,
      );
    } catch (e) {
      debugPrint('[HomeSearch] Exact profile lookup failed for $userId: $e');
      return null;
    }
  }

  String? _matrixUserIdFromQuery(String query) {
    var value = query.trim();
    if (!value.startsWith('@')) return null;
    value = value.substring(1);
    final separatorIndex = value.indexOf(':');
    final hasServer = separatorIndex >= 0;
    final localpart = hasServer ? value.substring(0, separatorIndex) : value;
    if (!RegExp(r'^[a-z0-9._=\-/]+$').hasMatch(localpart)) return null;
    if (hasServer) return query.trim();
    return '@$localpart:${MatrixService.matrixServerName}';
  }

  Future<void> _resolvePublicRoomTypes(List<PublicRoomsChunk> rooms) async {
    final provider = context.read<MatrixProvider>();
    final requestId = ++_publicRoomTypeRequestId;
    for (final room in rooms) {
      if (_publicRoomChannelFlags.containsKey(room.roomId)) continue;
      final isChannel = await provider.service.isPublicRoomChannel(
        room.roomId,
        forceRefresh: true,
      );
      if (!mounted || requestId != _publicRoomTypeRequestId) return;
      setState(() => _publicRoomChannelFlags[room.roomId] = isChannel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.select<MatrixProvider, bool>(
      (provider) => provider.isLoggedIn,
    );
    if (!isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthChoiceScreen()),
          (route) => false,
        );
      });
      return const Scaffold(backgroundColor: kBlack);
    }

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
                : const ChatList(),
          ),
        ],
      ),
      floatingActionButton: Consumer<ChatFilterProvider>(
        builder: (context, filterProvider, _) {
          if (filterProvider.filter == ChatFilter.stories ||
              filterProvider.filter == ChatFilter.calls) {
            return const SizedBox.shrink();
          }
          return const Padding(
            padding: EdgeInsets.only(bottom: 72),
            child: NewChatFAB(),
          );
        },
      ),
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
      if (r.membership != Membership.join &&
          r.membership != Membership.invite) {
        return false;
      }
      final nameMatches =
          matrixService.getResolvedDisplayName(r).toLowerCase().contains(query);
      final idMatches = directIdentifier != null && r.id == directIdentifier;
      return nameMatches || idMatches;
    }).toList();

    // Public room results (exclude all already-joined rooms).
    final joinedIds = matrixProvider.rooms
        .where((r) => r.membership == Membership.join)
        .map((r) => r.id)
        .toSet();
    final publicChannels =
        _publicResults.where((c) => !joinedIds.contains(c.roomId)).toList();

    if (localRooms.isEmpty &&
        _userResults.isEmpty &&
        publicChannels.isEmpty &&
        !_searchingPublic &&
        !_searchingUsers) {
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
        if (_userResults.isNotEmpty) ...[
          _sectionHeader('Users'),
          ..._userResults.map(
            (profile) => UserTile(
              key: ValueKey(profile.userId),
              profile: profile,
              onTap: () => _startDirectChat(profile),
            ),
          ),
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
        if (_searchingUsers)
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

  Future<void> _startDirectChat(Profile user) async {
    final userId = user.userId;
    if (userId.isEmpty) return;
    final provider = context.read<MatrixProvider>();

    final existingRoom = provider.findExistingDirectRoom(userId);
    if (existingRoom != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MatrixChatScreen(
            room: existingRoom,
            matrixProvider: provider,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePreviewScreen(profile: user),
      ),
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
    final joinedRoom = provider.service.getJoinedRoomById(chunk.roomId);
    final isJoined = joinedRoom != null;
    final isChannel =
        joinedRoom?.isChannel ?? _publicRoomChannelFlags[chunk.roomId] ?? false;
    final roomType = isChannel ? 'Channel' : 'Group';
    final roomIcon = isChannel ? Icons.campaign : Icons.group;

    return ListTile(
      tileColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF2C2C2E),
        child: Text(initial,
            style: GoogleFonts.inter(
                color: kLimeGreen, fontWeight: FontWeight.bold)),
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
          final room = provider.service.getJoinedRoomById(chunk.roomId);
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
                  previewChannel: chunk,
                  previewIsChannelHint: isChannel,
                  matrixProvider: provider,
                ),
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
                hintText: 'Search chats, channels, @users...',
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
