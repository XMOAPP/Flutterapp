import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/group_service.dart';
import '../../services/matrix_service.dart';
import '../../services/voip_service.dart';
import '../../services/report_service.dart';
import '../../models/report_models.dart';
import '../../models/group_models.dart';
import '../../widgets/incoming_call_fullscreen_scope.dart';
import '../../widgets/story/story_avatar.dart';
import '../../widgets/report_sheet.dart';
import '../direct_chat/shared_media_screen.dart';
import 'member_list_screen.dart';
import 'group_settings_screen.dart';
import 'add_members_screen.dart';
import 'admin_panel_screen.dart';
import 'invite_links_screen.dart';

/// Group Info Screen - Shows group details, members, and settings
enum GroupInfoResult { searchMessages }

class GroupInfoScreen extends StatefulWidget {
  final Room room;

  const GroupInfoScreen({super.key, required this.room});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late GroupService _groupService;
  List<GroupMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _groupService = GroupService(matrixProvider.service);
    _loadGroupData();
  }

  Future<void> _loadGroupData() async {
    setState(() => _loading = true);
    try {
      final members = await _groupService.getGroupMembers(widget.room.id);

      if (mounted) {
        setState(() {
          _members = members;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[GroupInfo] Error loading data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool get _canInvite =>
      GroupService.canInviteMembers(widget.room.ownPowerLevel.level);

  bool get _canEditSettings =>
      GroupService.canEditSettings(widget.room.ownPowerLevel.level);

  bool get _canManageAdmins =>
      GroupService.canManageAdmins(widget.room.ownPowerLevel.level);

  bool get _isOwner => widget.room.ownPowerLevel >= PowerLevel.admin;

  bool get _isAdminRole => _canEditSettings && !_isOwner;

  bool get _isModeratorRole => _canInvite && !_canEditSettings;

  bool get _isMemberRole => !_canInvite && !_canEditSettings && !_isOwner;

  @override
  Widget build(BuildContext context) {
    final memberCount =
        widget.room.summary.mJoinedMemberCount ?? _members.length;
    final groupName = MatrixService().getResolvedDisplayName(widget.room);
    final description = widget.room.topic;

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
            'Group Info',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 18,
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
              itemBuilder: (context) => _buildMenuItems(),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
            : SingleChildScrollView(
                child: Column(
                  children: [
                    // Group Header
                    _buildGroupHeader(groupName, memberCount),

                    // Description
                    if (description.isNotEmpty) _buildDescription(description),

                    const SizedBox(height: 16),

                    // Actions
                    _buildActionButtons(),

                    const SizedBox(height: 8),

                    // Members Section
                    _buildMembersSection(),

                    const SizedBox(height: 8),

                    _buildSharedMediaSection(),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildGroupHeader(String name, int memberCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        children: [
          // Group Avatar
          StoryAvatar(
            userName: name,
            avatarUrl: widget.room.avatar?.toString(),
            size: 100,
            fallbackIcon: Icons.group,
          ),
          const SizedBox(height: 16),

          // Group Name
          Text(
            name,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Member Count
          Text(
            '$memberCount members',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      if (_isOwner || _canEditSettings)
        _buildMenuItem(value: 'edit', icon: Icons.edit, label: 'Edit Group'),
      if (_isOwner)
        _buildMenuItem(
          value: 'delete',
          icon: Icons.delete,
          label: 'Delete Group',
          destructive: true,
        )
      else
        _buildMenuItem(
          value: 'leave',
          icon: Icons.logout,
          label: 'Leave Group',
          destructive: true,
        ),
      _buildMenuItem(
        value: 'report',
        icon: Icons.flag_outlined,
        label: 'Report Group',
        destructive: true,
      ),
    ];
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
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(String action) async {
    switch (action) {
      case 'delete':
        _confirmDeleteGroup();
        break;
      case 'leave':
        _confirmLeaveGroup();
        break;
      case 'voice':
      case 'video':
        await _startGroupCall(video: action == 'video');
        break;
      case 'search':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MemberListScreen(room: widget.room, members: _members),
          ),
        ).then((_) => _loadGroupData());
        break;
      case 'edit':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupSettingsScreen(room: widget.room),
          ),
        ).then((_) => _loadGroupData());
        break;
      case 'report':
        final service = context.read<MatrixProvider>().service;
        final submitted = await showXmoReportSheet(
          context: context,
          reportService: ReportService(service),
          targetType: XmoReportTargetType.group,
          contextType: XmoReportContextType.group,
          title: 'Report group',
          roomId: widget.room.id,
        );
        if (submitted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Report submitted'),
              backgroundColor: kLimeGreen,
            ),
          );
        }
        break;
    }
  }

  Future<void> _startGroupCall({required bool video}) async {
    try {
      await VoipService().startCall(widget.room, video: video);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to start ${video ? 'video' : 'voice'} call: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleMute() async {
    final shouldMute = widget.room.pushRuleState != PushRuleState.dontNotify;

    try {
      await widget.room.setPushRuleState(
        shouldMute ? PushRuleState.dontNotify : PushRuleState.notify,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shouldMute ? 'Group muted' : 'Group unmuted'),
          backgroundColor: kLimeGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update mute: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openSearch() {
    Navigator.pop(context, GroupInfoResult.searchMessages);
  }

  Future<void> _confirmLeaveGroup() async {
    final provider = context.read<MatrixProvider>();
    final confirmed = await _confirmAction(
      title: 'Leave Group?',
      message: 'Leave this group?',
      actionLabel: 'Leave',
    );
    if (confirmed != true) return;

    try {
      await widget.room.leave();
      try {
        await provider.service.client.oneShotSync();
      } catch (_) {}
      provider.refreshRooms();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to leave group: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteGroup() async {
    final confirmed = await _confirmAction(
      title: 'Delete Group?',
      message: 'Delete this group for everyone you can remove?',
      actionLabel: 'Delete',
    );
    if (confirmed != true) return;

    try {
      await _groupService.deleteGroup(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete group: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool?> _confirmAction({
    required String title,
    required String message,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262728),
        title: Text(title, style: GoogleFonts.inter(color: kWhite)),
        content: Text(message, style: GoogleFonts.inter(color: kLightGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              actionLabel,
              style: GoogleFonts.inter(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(String description) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: GoogleFonts.inter(color: kWhite, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final isMuted = widget.room.pushRuleState == PushRuleState.dontNotify;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 24) / 4;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_canInvite)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.person_add,
                  label: 'Add Members',
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddMembersScreen(room: widget.room),
                      ),
                    );
                    // Reload data if members were added
                    if (result == true) {
                      _loadGroupData();
                    }
                  },
                ),
              if (_canInvite)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.link,
                  label: 'Invite Link',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InviteLinksScreen(room: widget.room),
                      ),
                    );
                  },
                ),
              if (_canEditSettings)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.settings,
                  label: 'Settings',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupSettingsScreen(room: widget.room),
                      ),
                    ).then((_) => _loadGroupData());
                  },
                ),
              if (_isAdminRole || _isModeratorRole || _isMemberRole)
                _buildActionButton(
                  width: itemWidth,
                  icon: isMuted
                      ? Icons.notifications_active
                      : Icons.notifications_off,
                  label: isMuted ? 'Unmute' : 'Mute',
                  onTap: _toggleMute,
                ),
              if (_isModeratorRole || _isMemberRole)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.search,
                  label: 'Search',
                  onTap: _openSearch,
                ),
              if (_isMemberRole)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.call,
                  label: 'Voice',
                  onTap: () => _startGroupCall(video: false),
                ),
              if (_isMemberRole)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.videocam,
                  label: 'Video',
                  onTap: () => _startGroupCall(video: true),
                ),
              if (_canManageAdmins)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.admin_panel_settings,
                  label: 'Admin Panel',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminPanelScreen(room: widget.room),
                      ),
                    ).then((_) => _loadGroupData());
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required double width,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: kLimeGreen, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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

  Widget _buildMembersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: const Icon(Icons.group, color: kLimeGreen, size: 20),
            title: Text(
              'Members',
              style: GoogleFonts.inter(
                color: kWhite,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_members.length}',
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      MemberListScreen(room: widget.room, members: _members),
                ),
              ).then((_) => _loadGroupData());
            },
          ),
          // Show first 3 members
          ..._members
              .take(3)
              .map((member) => _buildMemberTile(member, showRole: true)),
          if (_members.length > 3)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'and ${_members.length - 3} more...',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(GroupMember member, {bool showRole = false}) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      minLeadingWidth: 46,
      horizontalTitleGap: 12,
      leading: StoryAvatar(
        userName: member.displayName,
        avatarUrl: member.avatarUrl,
        size: 46,
      ),
      title: Text(
        member.displayName,
        style: GoogleFonts.inter(color: kWhite, fontSize: 13),
      ),
      trailing: showRole ? _buildRoleBadge(member.role) : null,
    );
  }

  Widget _buildRoleBadge(MemberRole role) {
    String label;
    Color color;

    switch (role) {
      case MemberRole.owner:
        label = 'Owner';
        color = const Color(0xFFFFD700); // Gold
        break;
      case MemberRole.admin:
        label = 'Admin';
        color = kLimeGreen;
        break;
      case MemberRole.moderator:
        label = 'Mod';
        color = const Color(0xFF3B82F6); // Blue
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
