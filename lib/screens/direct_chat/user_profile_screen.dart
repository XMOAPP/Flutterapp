import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/direct_chat_service.dart';
import '../../models/direct_chat_models.dart';
import 'shared_media_screen.dart';
import 'chat_settings_screen.dart';
import 'search_in_chat_screen.dart';

/// User Profile Screen for Direct Chats
class UserProfileScreen extends StatefulWidget {
  final Room room;
  final String userId;

  const UserProfileScreen({
    super.key,
    required this.room,
    required this.userId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late DirectChatService _directChatService;
  DirectChatProfile? _profile;
  bool _loading = true;
  bool _isBlocked = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _directChatService = DirectChatService(matrixProvider.service);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final profile = await _directChatService.getUserProfile(
        widget.room.id,
        widget.userId,
      );
      final isBlocked = _directChatService.isUserBlocked(widget.userId);
      final settings = await _directChatService.getChatSettings(widget.room.id);

      if (mounted) {
        setState(() {
          _profile = profile;
          _isBlocked = isBlocked;
          _isMuted = settings.isMuted;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[UserProfile] Error loading profile: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggleBlock() async {
    try {
      if (_isBlocked) {
        await _directChatService.unblockUser(widget.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User unblocked'),
              backgroundColor: kLimeGreen,
            ),
          );
        }
      } else {
        final confirmed = await _showBlockConfirmation();
        if (confirmed == true) {
          await _directChatService.blockUser(widget.userId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('User blocked'),
                backgroundColor: kLimeGreen,
              ),
            );
          }
        } else {
          return;
        }
      }
      setState(() => _isBlocked = !_isBlocked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool?> _showBlockConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Block User?', style: GoogleFonts.inter(color: kWhite)),
        content: Text(
          'Blocked users cannot send you messages or see your online status.',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Block', style: GoogleFonts.inter(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMute() async {
    try {
      await _directChatService.toggleMute(widget.room.id, !_isMuted);
      setState(() => _isMuted = !_isMuted);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isMuted ? 'Chat muted' : 'Chat unmuted'),
            backgroundColor: kLimeGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Clear Chat?', style: GoogleFonts.inter(color: kWhite)),
        content: Text(
          'This will delete all messages in this chat. This action cannot be undone.',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear', style: GoogleFonts.inter(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _directChatService.clearChatHistory(widget.room.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat cleared'),
            backgroundColor: kLimeGreen,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          'Contact Info',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : _profile == null
              ? Center(
                  child: Text(
                    'Failed to load profile',
                    style: GoogleFonts.inter(color: kLightGrey),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      // Profile Header
                      _buildProfileHeader(),
                      const SizedBox(height: 24),

                      // Status
                      _buildStatusSection(),
                      const SizedBox(height: 8),

                      // Actions
                      _buildActionsSection(),
                      const SizedBox(height: 8),

                      // Shared Media
                      _buildSharedMediaSection(),
                      const SizedBox(height: 8),

                      // Settings
                      _buildSettingsSection(),
                      const SizedBox(height: 8),

                      // Danger Zone
                      _buildDangerZoneSection(),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: kLimeGreen,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _profile!.displayName.isNotEmpty
                    ? _profile!.displayName[0].toUpperCase()
                    : '?',
                style: GoogleFonts.inter(
                  color: kBlack,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            _profile!.displayName,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _profile!.isOnline ? Icons.circle : Icons.circle_outlined,
            color: _profile!.isOnline ? kLimeGreen : kLightGrey,
            size: 10,
          ),
          const SizedBox(width: 7),
          Text(
            _profile!.isOnline
                ? 'Online'
                : _profile!.lastSeen != null
                    ? 'Last seen ${_formatLastSeen(_profile!.lastSeen!)}'
                    : 'Offline',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Icon(
              _isMuted ? Icons.notifications_off : Icons.notifications_outlined,
              color: kLimeGreen,
              size: 20,
            ),
            title: Text(
              _isMuted ? 'Unmute' : 'Mute',
              style: GoogleFonts.inter(color: kWhite, fontSize: 14),
            ),
            trailing: const Icon(Icons.chevron_right, color: kLightGrey, size: 18),
            onTap: _toggleMute,
          ),
          const Divider(color: kMediumGrey, height: 1),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: const Icon(Icons.search, color: kLimeGreen, size: 20),
            title: Text(
              'Search in Chat',
              style: GoogleFonts.inter(color: kWhite, fontSize: 14),
            ),
            trailing: const Icon(Icons.chevron_right, color: kLightGrey, size: 18),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SearchInChatScreen(room: widget.room),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSharedMediaSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: const Icon(Icons.photo_library_outlined, color: kLimeGreen, size: 20),
        title: Text(
          'Shared Media',
          style: GoogleFonts.inter(color: kWhite, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          '${_profile!.sharedMediaCount} items',
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right, color: kLightGrey, size: 18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SharedMediaScreen(room: widget.room),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: const Icon(Icons.settings_outlined, color: kLimeGreen, size: 20),
        title: Text(
          'Chat Settings',
          style: GoogleFonts.inter(color: kWhite, fontSize: 14),
        ),
        trailing: const Icon(Icons.chevron_right, color: kLightGrey, size: 18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatSettingsScreen(room: widget.room),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDangerZoneSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Icon(
              _isBlocked ? Icons.check_circle : Icons.block,
              color: Colors.orange,
              size: 20,
            ),
            title: Text(
              _isBlocked ? 'Unblock User' : 'Block User',
              style: GoogleFonts.inter(color: Colors.orange, fontSize: 14),
            ),
            onTap: _toggleBlock,
          ),
          const Divider(color: kMediumGrey, height: 1),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            title: Text(
              'Clear Chat',
              style: GoogleFonts.inter(color: Colors.red, fontSize: 14),
            ),
            onTap: _clearChat,
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    }
  }
}
