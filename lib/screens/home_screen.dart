import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../theme.dart';
import '../models/data_models.dart';
import '../providers/chat_filter_provider.dart';
import '../providers/matrix_provider.dart';
import '../services/matrix_service.dart';
import '../screens/chat_screen.dart';
import '../screens/matrix_chat_screen.dart';
import '../screens/stories_screen.dart';
import '../screens/login_screen.dart';
import '../screens/user_search_screen.dart';
import '../widgets/chat_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
    });
    context.read<ChatFilterProvider>().setSearchQuery('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      drawer: const _XmoDrawer(),
      appBar: AppBar(
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
                style: GoogleFonts.inter(color: kWhite),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: GoogleFonts.inter(color: kLightGrey),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  context.read<ChatFilterProvider>().setSearchQuery(value);
                },
                autofocus: true,
              )
            : Text(
                'xmo',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: kWhite,
              size: 24,
            ),
            onPressed: () {
              if (_isSearching) {
                _stopSearch();
              } else {
                _startSearch();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isSearching) const _CategoryFilters(),
          if (!_isSearching) const SizedBox(height: 4),
          Expanded(child: _ChatBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kLimeGreen,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UserSearchScreen()),
          );
        },
        child: const Icon(Icons.chat_outlined, color: kBlack, size: 24),
      ),
    );
  }
}

class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatFilterProvider>();
    final filter = provider.filter;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            badge: '20',
            isSelected: filter == ChatFilter.all,
            onTap: () => provider.setFilter(ChatFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Groups',
            badge: '17',
            isSelected: filter == ChatFilter.groups,
            onTap: () => provider.setFilter(ChatFilter.groups),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Stories',
            badge: '11',
            isSelected: filter == ChatFilter.stories,
            onTap: () => provider.setFilter(ChatFilter.stories),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String badge;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.badge,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kLimeGreen : kDarkGrey,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: isSelected ? kBlack : kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? kBlack.withValues(alpha: 0.25) : kLimeGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: GoogleFonts.inter(
                  color: isSelected ? kBlack : kBlack,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final filterProvider = context.watch<ChatFilterProvider>();
    final matrixProvider = context.watch<MatrixProvider>();
    final filter = filterProvider.filter;
    final searchQuery = filterProvider.searchQuery.toLowerCase();

    if (filter == ChatFilter.stories && searchQuery.isEmpty) {
      return const StoriesScreen();
    }

    final allChats =
        filter == ChatFilter.groups ? MockData.groupChats : MockData.allChats;

    final chats = allChats.where((chat) {
      final nameMatches = chat.name.toLowerCase().contains(searchQuery);
      final messageMatches =
          chat.lastMessage.toLowerCase().contains(searchQuery);
      return nameMatches || messageMatches;
    }).toList();

    // Real Matrix rooms from the SDK
    final matrixRooms = matrixProvider.isLoggedIn
        ? matrixProvider.rooms.where((r) {
            final name = r.getLocalizedDisplayname().toLowerCase();
            return searchQuery.isEmpty || name.contains(searchQuery);
          }).toList()
        : [];

    final totalCount = chats.length + (matrixRooms.isNotEmpty ? matrixRooms.length + 1 : 0);

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // Matrix section header + rooms shown FIRST
        if (matrixRooms.isNotEmpty) {
          if (index == 0) {
            // Section header
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: kLimeGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Matrix Rooms',
                    style: GoogleFonts.inter(
                      color: kLimeGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: kLimeGreen,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${matrixRooms.length}',
                      style: GoogleFonts.inter(
                          color: kBlack,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }
          if (index <= matrixRooms.length) {
            final room = matrixRooms[index - 1];
            final rawName = room.getLocalizedDisplayname();
            final memberCount = room.summary.mJoinedMemberCount ?? 0;
            final isDirect = memberCount == 2;
            
            // For direct chats, clean up the name (remove "Group with" prefix)
            String displayName = rawName;
            if (isDirect) {
              // Remove "Group with " prefix if present
              if (displayName.toLowerCase().startsWith('group with ')) {
                displayName = displayName.substring(11);
              }
              // Remove "Direct Room with " prefix if present
              if (displayName.toLowerCase().startsWith('direct room with ')) {
                displayName = displayName.substring(17);
              }
            }
            final cleanedName = MatrixService.cleanName(displayName);
            
            // Get the last message properly
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: kLimeGreen,
                child: Text(
                  cleanedName.isNotEmpty ? cleanedName[0].toUpperCase() : '#',
                  style: GoogleFonts.inter(
                      color: kBlack, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(
                cleanedName,
                style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                lastMsg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
              ),
              // Only show member count badge for groups (3+ members)
              trailing: !isDirect ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kLimeGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people, color: kLimeGreen, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '$memberCount',
                      style: GoogleFonts.inter(
                        color: kLimeGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ) : null,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MatrixChatScreen(
                      room: room,
                      matrixProvider: matrixProvider,
                    ),
                  ),
                );
              },
            );
          }
        }

        // Mock chats below
        final chatIndex = matrixRooms.isNotEmpty
            ? index - matrixRooms.length - 1
            : index;
        final chat = chats[chatIndex];
        return ChatTile(
          chat: chat,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
            );
          },
        );
      },
    );
  }
}

class _XmoDrawer extends StatelessWidget {
  const _XmoDrawer();

  @override
  Widget build(BuildContext context) {
    final matrixProvider = context.watch<MatrixProvider>();
    final displayName = matrixProvider.displayName ?? 'Unknown';
    final userId = matrixProvider.userId ?? '';

    return Drawer(
      backgroundColor: const Color(0xFF0F0F0F),
      child: SafeArea(
        child: Column(
          children: [
            // ── User header ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: kLimeGreen,
                    radius: 22,
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.inter(
                          color: kBlack,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.inter(
                              color: kWhite,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          userId.contains(':') ? '@${MatrixService.cleanName(userId)}' : userId,
                          style: GoogleFonts.inter(
                              color: kLightGrey, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: kDarkGrey, height: 1),
            const SizedBox(height: 8),

            // ── Create Matrix Room ─────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.add_circle_outline,
                  color: kLimeGreen, size: 22),
              title: Text(
                'New Matrix Room',
                style: GoogleFonts.inter(
                    color: kLimeGreen,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              onTap: () {
                Navigator.pop(context);
                _showCreateRoomDialog(context, matrixProvider);
              },
            ),

            // ── Static items ───────────────────────────────────────────
            ...[
              {'icon': Icons.person_outline, 'label': 'My Profile'},
              {'icon': Icons.contacts_outlined, 'label': 'Contacts'},
              {'icon': Icons.phone_outlined, 'label': 'Calls'},
              {'icon': Icons.bookmark_outline, 'label': 'Saved Messages'},
              {'icon': Icons.settings_outlined, 'label': 'Settings'},
              {'icon': Icons.info_outline, 'label': 'About xmo'},
            ].map((item) => ListTile(
                  leading: Icon(item['icon'] as IconData,
                      color: kWhite, size: 22),
                  title: Text(
                    item['label'] as String,
                    style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w500),
                  ),
                  onTap: () => Navigator.pop(context),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 2),
                )),

            const Spacer(),
            const Divider(color: kDarkGrey, height: 1),

            // ── Logout ────────────────────────────────────────────────
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red[400], size: 22),
              title: Text(
                'Logout',
                style: GoogleFonts.inter(
                    color: Colors.red[400],
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              onTap: () async {
                Navigator.pop(context);
                await matrixProvider.logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCreateRoomDialog(BuildContext context, MatrixProvider provider) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kDarkerGrey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('New Matrix Room',
            style: GoogleFonts.inter(
                color: kWhite, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.inter(color: kWhite),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Room name',
            hintStyle: GoogleFonts.inter(color: kLightGrey),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: kDarkGrey)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: kLimeGreen)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              await provider.createRoom(ctrl.text.trim());
            },
            child: Text('Create',
                style: GoogleFonts.inter(
                    color: kLimeGreen, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
