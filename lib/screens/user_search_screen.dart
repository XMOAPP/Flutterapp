import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/matrix_service.dart';
import '../theme.dart';
import 'matrix_chat_screen.dart';

/// Search for users by username and start a direct chat.
class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _searchCtrl = TextEditingController();
  List<Profile> _results = [];
  bool _searching = false;
  bool _startingChat = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    final provider = context.read<MatrixProvider>();
    
    // First try: Search user directory
    final results = await provider.searchUsers(query);

    // Filter out the current user from results
    final myId = provider.userId;
    final filtered = results.where((p) => p.userId != myId).toList();

    // If directory search found results, show them
    if (filtered.isNotEmpty) {
      if (mounted) {
        setState(() {
          _results = filtered;
          _searching = false;
        });
      }
      return;
    }

    // Second try: Treat query as a direct Matrix ID
    // Normalize the Matrix ID
    String matrixId = query.trim();
    if (!matrixId.startsWith('@')) {
      matrixId = '@$matrixId';
    }
    if (!matrixId.contains(':')) {
      matrixId = '$matrixId:localhost';
    }

    // Try to get user profile directly
    try {
      final profile = await provider.service.client.getProfileFromUserId(matrixId);
      
      if (mounted && profile.userId != myId) {
        setState(() {
          _results = [profile];
          _searching = false;
        });
        return;
      }
    } catch (e) {
      // User doesn't exist or error occurred
      debugPrint('Direct Matrix ID lookup failed: $e');
    }

    // No results from either method
    if (mounted) {
      setState(() {
        _results = [];
        _searching = false;
        _error = 'No user found for "$query"\n\nTry entering the exact username (e.g., "kiran" or "kiranpeter")';
      });
    }
  }

  Future<void> _startChat(Profile user) async {
    setState(() => _startingChat = true);
    final provider = context.read<MatrixProvider>();
    final roomId = await provider.startDirectChat(user.userId);

    if (!mounted) return;
    setState(() => _startingChat = false);

    if (roomId != null) {
      final room = provider.service.getRoomById(roomId);
      if (room != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MatrixChatScreen(
              room: room,
              matrixProvider: provider,
            ),
          ),
        );
      }
    } else {
      setState(() => _error = provider.error ?? 'Could not start chat.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'New Chat',
          style: GoogleFonts.inter(
              color: kWhite, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: kDarkGrey,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by username...',
                  hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: kLightGrey, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: kLightGrey, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _results = [];
                              _error = null;
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),

          // ── Loading / starting chat overlay ──────────────────────────────
          if (_startingChat)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: kLimeGreen),
                    SizedBox(height: 12),
                    Text('Starting chat...',
                        style: TextStyle(color: kLightGrey, fontSize: 13)),
                  ],
                ),
              ),
            ),

          // ── Search indicator ─────────────────────────────────────────────
          if (_searching && !_startingChat)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: kLimeGreen),
              ),
            ),

          // ── Error / empty state ──────────────────────────────────────────
          if (_error != null && !_searching && !_startingChat)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.person_search_outlined,
                        color: kMediumGrey, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: kLightGrey, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),

          // ── Empty initial state ──────────────────────────────────────────
          if (_results.isEmpty &&
              !_searching &&
              !_startingChat &&
              _error == null &&
              _searchCtrl.text.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        color: kLimeGreen.withValues(alpha: 0.3), size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Search for a user to start chatting',
                      style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Type a username or Matrix ID',
                      style: GoogleFonts.inter(
                          color: kMediumGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Examples: kiran, @kiran:localhost',
                      style: GoogleFonts.inter(
                          color: kMediumGrey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

          // ── Results ─────────────────────────────────────────────────────
          if (_results.isNotEmpty && !_startingChat)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _results.length,
                itemBuilder: (_, i) => _UserTile(
                  profile: _results[i],
                  onTap: () => _startChat(_results[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserTile extends StatefulWidget {
  final Profile profile;
  final VoidCallback onTap;

  const _UserTile({required this.profile, required this.onTap});

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cleanUsername = MatrixService.cleanName(widget.profile.userId);
    final displayName = widget.profile.displayName;
    final hasDisplayName =
        displayName != null && displayName.isNotEmpty && displayName != cleanUsername;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? kDarkGrey : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kLimeGreen.withValues(alpha: 0.8),
                      kLimeGreen,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    cleanUsername.isNotEmpty
                        ? cleanUsername[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.inter(
                        color: kBlack,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Name & username
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasDisplayName ? displayName : cleanUsername,
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasDisplayName)
                      Text(
                        '@$cleanUsername',
                        style: GoogleFonts.inter(
                            color: kLightGrey, fontSize: 12),
                      ),
                  ],
                ),
              ),

              // Chat icon
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _hovered ? 1.0 : 0.4,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kLimeGreen.withValues(alpha: _hovered ? 0.2 : 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline,
                      color: kLimeGreen, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
