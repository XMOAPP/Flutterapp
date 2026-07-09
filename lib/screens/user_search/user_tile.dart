import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../services/matrix_service.dart';
import '../../theme.dart';
import '../../widgets/story/story_avatar.dart';

// ═══════════════════════════════════════════════════════════════════════════
// USER TILE - Optimized with RepaintBoundary
// ═══════════════════════════════════════════════════════════════════════════

class UserTile extends StatefulWidget {
  final Profile profile;
  final VoidCallback onTap;

  const UserTile({super.key, required this.profile, required this.onTap});

  @override
  State<UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<UserTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cleanUsername = MatrixService.cleanName(widget.profile.userId);
    final displayName = widget.profile.displayName;
    final hasDisplayName = displayName != null && displayName.isNotEmpty;

    return RepaintBoundary(
      child: MouseRegion(
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
                _buildAvatar(cleanUsername),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildUserInfo(
                    cleanUsername,
                    displayName,
                    hasDisplayName,
                  ),
                ),
                _buildChatIcon(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String cleanUsername) {
    return StoryAvatar(
      userName: cleanUsername,
      avatarUrl: widget.profile.avatarUrl?.toString(),
      size: 46,
    );
  }

  Widget _buildUserInfo(
    String cleanUsername,
    String? displayName,
    bool hasDisplayName,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasDisplayName ? displayName! : cleanUsername,
          style: _nameTextStyle,
        ),
        Text(
          '@$cleanUsername',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _usernameTextStyle,
        ),
      ],
    );
  }

  Widget _buildChatIcon() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: _hovered ? 1.0 : 0.4,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: kLimeGreen.withValues(alpha: _hovered ? 0.2 : 0.08),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.chat_bubble_outline,
          color: kLimeGreen,
          size: 16,
        ),
      ),
    );
  }

  static final _nameTextStyle = GoogleFonts.inter(
    color: kWhite,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static final _usernameTextStyle = GoogleFonts.inter(
    color: kLightGrey,
    fontSize: 12,
  );
}
