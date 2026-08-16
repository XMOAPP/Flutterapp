import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/direct_chat_service.dart';
import '../../services/voip_service.dart';
import '../../services/report_service.dart';
import '../../models/report_models.dart';
import '../../models/direct_chat_models.dart';
import '../../models/xmo_contact_card.dart';
import '../../widgets/incoming_call_fullscreen_scope.dart';
import '../../widgets/story/story_avatar.dart';
import '../../widgets/report_sheet.dart';
import 'shared_media_screen.dart';
import '../matrix_chat/forward_message_sheet.dart';

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
  bool _sharingContact = false;

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
            content: Text(safeUserFacingText('Failed: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _reportUser() async {
    final matrixService = context.read<MatrixProvider>().service;
    final submitted = await showXmoReportSheet(
      context: context,
      reportService: ReportService(matrixService),
      targetType: XmoReportTargetType.user,
      contextType: XmoReportContextType.direct,
      title: 'Report user',
      reportedUserId: widget.userId,
      roomId: widget.room.id,
      blockUser: _isBlocked
          ? null
          : () async {
              await _directChatService.blockUser(widget.userId);
              if (mounted) setState(() => _isBlocked = true);
            },
    );
    if (submitted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted'),
          backgroundColor: kLimeGreen,
        ),
      );
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
            content: Text(safeUserFacingText('Failed: $e')),
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
            content: Text(safeUserFacingText('Failed: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startDirectCall(bool video) async {
    try {
      await VoipService().startCall(widget.room, video: video);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeUserFacingText(
              'Unable to start ${video ? 'video' : 'voice'} call: $e',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareContact() async {
    if (_sharingContact) return;
    final matrixProvider = context.read<MatrixProvider>();
    final username = _xmoUsernameFromUserId(widget.userId);
    final displayName = _profile?.displayName.trim().isNotEmpty == true
        ? _profile!.displayName.trim()
        : username;

    final selectedRooms = await showForwardMessageSheet(
      context: context,
      rooms: matrixProvider.rooms,
      currentRoom: widget.room,
      title: 'Share contact with',
      actionLabel: 'Share',
      emptyLabel: 'No chats available',
      previewLabel: displayName,
      previewIcon: Icons.person_rounded,
    );
    if (!mounted || selectedRooms == null || selectedRooms.isEmpty) return;

    setState(() => _sharingContact = true);
    try {
      final contact = XmoContactCard.createXmoUser(
        displayName: displayName,
        userId: widget.userId,
        username: username,
        avatarUrl: _profile?.avatarUrl,
      );
      for (final room in selectedRooms) {
        await matrixProvider.service.sendFileWithProgress(
          roomId: room.id,
          bytes: contact.toVCardBytes(),
          fileName: contact.fileName,
          mimeType: 'text/vcard',
          xmoContact: contact.toJson(),
        );
      }
      if (!mounted) return;
      final count = selectedRooms.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1 ? 'Contact shared' : 'Contact shared to $count chats',
          ),
          backgroundColor: kLimeGreen,
        ),
      );
      matrixProvider.refreshRooms();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to share contact. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingContact = false);
    }
  }

  String _xmoUsernameFromUserId(String userId) {
    final withoutAt = userId.startsWith('@') ? userId.substring(1) : userId;
    final localpart = withoutAt.split(':').first.trim();
    return localpart.isEmpty ? userId : '@$localpart';
  }

  void _archiveChat() {
    Navigator.pop(context, true);
  }

  void _handleMenuAction(String value) {
    switch (value) {
      case 'share':
        _shareContact();
        break;
      case 'archive':
        _archiveChat();
        break;
      case 'block':
        _toggleBlock();
        break;
      case 'report':
        _reportUser();
        break;
      case 'clear':
        _clearChat();
        break;
    }
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool destructive = false,
  }) {
    final color = destructive ? Colors.redAccent : kWhite;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      _buildMenuItem(value: 'share', icon: Icons.share, label: 'Share Contact'),
      _buildMenuItem(
        value: 'archive',
        icon: Icons.archive_outlined,
        label: 'Archive Chat',
      ),
      _buildMenuItem(
        value: 'block',
        icon: _isBlocked ? Icons.check_circle : Icons.block,
        label: _isBlocked ? 'Unblock User' : 'Block User',
        destructive: true,
      ),
      _buildMenuItem(
        value: 'report',
        icon: Icons.flag_outlined,
        label: 'Report User',
        destructive: true,
      ),
      _buildMenuItem(
        value: 'clear',
        icon: Icons.delete,
        label: 'Clear Chat',
        destructive: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return IncomingCallFullscreenScope(
      child: Scaffold(
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
          actions: [
            PopupMenuButton<String>(
              color: const Color(0xFF262728),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              icon: const Icon(Icons.more_vert, color: kWhite, size: 28),
              onSelected: _handleMenuAction,
              itemBuilder: (_) => _buildMenuItems(),
            ),
          ],
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

                    // Actions
                    _buildActionsSection(),
                    const SizedBox(height: 8),

                    // Shared Media
                    _buildSharedMediaSection(),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final displayName = _profile!.displayName;
    final username = _xmoUsernameFromUserId(widget.userId);
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          StoryAvatar(
            userName: displayName,
            avatarUrl: _profile!.avatarUrl,
            size: 80,
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            displayName,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            username,
            style: GoogleFonts.inter(
              color: kLightGrey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              icon: _isMuted ? Icons.notifications_off : Icons.notifications,
              label: _isMuted ? 'Unmute' : 'Mute',
              onTap: _toggleMute,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              icon: Icons.call,
              label: 'Call',
              onTap: () => _startDirectCall(false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              icon: Icons.videocam,
              label: 'Video',
              onTap: () => _startDirectCall(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              icon: Icons.message,
              label: 'Message',
              onTap: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: kLimeGreen, size: 24),
            const SizedBox(height: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSharedMediaSection() {
    return SharedMediaScreen(
      room: widget.room,
      embedded: true,
      showDivider: false,
    );
  }
}
