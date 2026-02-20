import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/data_models.dart';
import '../providers/chat_filter_provider.dart';
import '../screens/chat_screen.dart';
import '../screens/stories_screen.dart';
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
    final provider = context.watch<ChatFilterProvider>();
    final filter = provider.filter;
    final searchQuery = provider.searchQuery.toLowerCase();

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

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
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
    const items = [
      {'icon': Icons.person_outline, 'label': 'My Profile'},
      {'icon': Icons.group_outlined, 'label': 'New Group'},
      {'icon': Icons.contacts_outlined, 'label': 'Contacts'},
      {'icon': Icons.phone_outlined, 'label': 'Calls'},
      {'icon': Icons.bookmark_outline, 'label': 'Saved Messages'},
      {'icon': Icons.settings_outlined, 'label': 'Settings'},
      {'icon': Icons.person_add_outlined, 'label': 'Invite Friends'},
      {'icon': Icons.info_outline, 'label': 'About xmo'},
      {'icon': Icons.logout, 'label': 'Logout'},
    ];

    return Drawer(
      backgroundColor: const Color(0xFF0F0F0F),
      child: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final isLogout = item['label'] == 'Logout';
            return ListTile(
              leading: Icon(
                item['icon'] as IconData,
                color: isLogout ? Colors.red[400] : kWhite,
                size: 22,
              ),
              title: Text(
                item['label'] as String,
                style: GoogleFonts.inter(
                  color: isLogout ? Colors.red[400] : kWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => Navigator.pop(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 2,
              ),
            );
          },
        ),
      ),
    );
  }
}
