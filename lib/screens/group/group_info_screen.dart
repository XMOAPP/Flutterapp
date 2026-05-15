import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/group_service.dart';
import '../../services/matrix_service.dart';
import '../../models/group_models.dart';
import '../../widgets/story/story_avatar.dart';
import '../direct_chat/shared_media_screen.dart';
import 'member_list_screen.dart';
import 'group_settings_screen.dart';
import 'add_members_screen.dart';
import 'admin_panel_screen.dart';
import 'invite_links_screen.dart';

/// Group Info Screen - Shows group details, members, admins, and settings
class GroupInfoScreen extends StatefulWidget {
  final Room room;

  const GroupInfoScreen({super.key, required this.room});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late GroupService _groupService;
  List<GroupMember> _members = [];
  List<GroupMember> _admins = [];
  int _sharedMediaCount = 0;
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
      final admins = members.where((m) => m.powerLevel >= 25).toList();
      final sharedMediaCount = await _loadSharedMediaCount();

      if (mounted) {
        setState(() {
          _members = members;
          _admins = admins;
          _sharedMediaCount = sharedMediaCount;
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

  Future<int> _loadSharedMediaCount() async {
    final timeline = await widget.room.getTimeline();
    return timeline.events.where((event) {
      final msgType = event.messageType;
      return msgType == MessageTypes.Image ||
          msgType == MessageTypes.Video ||
          msgType == MessageTypes.Audio ||
          msgType == MessageTypes.File;
    }).length;
  }

  bool get _canInvite =>
      GroupService.canInviteMembers(widget.room.ownPowerLevel);

  bool get _canEditSettings =>
      GroupService.canEditSettings(widget.room.ownPowerLevel);

  bool get _canManageAdmins =>
      GroupService.canManageAdmins(widget.room.ownPowerLevel);

  @override
  Widget build(BuildContext context) {
    final memberCount =
        widget.room.summary.mJoinedMemberCount ?? _members.length;
    final groupName = MatrixService().getResolvedDisplayName(widget.room);
    final description = widget.room.topic;

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
          'Group Info',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
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

                  _buildSharedMediaSection(),

                  const SizedBox(height: 8),

                  // Members Section
                  _buildMembersSection(),

                  // Admins Section
                  if (_admins.isNotEmpty) _buildAdminsSection(),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildGroupHeader(String name, int memberCount) {
    return Container(
      padding: const EdgeInsets.all(24),
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
            style: GoogleFonts.inter(
              color: kLightGrey,
              fontSize: 14,
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
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Description',
            style: GoogleFonts.inter(
              color: kLightGrey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
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
                icon: Icons.person_add_outlined,
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
              _buildActionButton(
                width: itemWidth,
              icon: Icons.link_outlined,
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
                icon: Icons.settings_outlined,
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
              if (_canManageAdmins)
                _buildActionButton(
                  width: itemWidth,
                icon: Icons.admin_panel_settings_outlined,
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: kDarkerGrey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: kLimeGreen, size: 20),
              const SizedBox(height: 6),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(
          Icons.photo_library_outlined,
          color: kLimeGreen,
          size: 22,
        ),
        title: Text(
          'Shared Media',
          style: GoogleFonts.inter(
            color: kWhite,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          '$_sharedMediaCount item${_sharedMediaCount == 1 ? '' : 's'}',
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

  Widget _buildMembersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading:
                const Icon(Icons.group_outlined, color: kLimeGreen, size: 20),
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
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: kLightGrey, size: 18),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemberListScreen(
                    room: widget.room,
                    members: _members,
                  ),
                ),
              ).then((_) => _loadGroupData());
            },
          ),
          // Show first 3 members
          ..._members.take(3).map((member) => _buildMemberTile(member)),
          if (_members.length > 3)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'and ${_members.length - 3} more...',
                style: GoogleFonts.inter(
                  color: kLightGrey,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAdminsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.admin_panel_settings_outlined,
                color: kLimeGreen, size: 20),
            title: Text(
              'Admins',
              style: GoogleFonts.inter(
                color: kWhite,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            trailing: Text(
              '${_admins.length}',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
            ),
          ),
          ..._admins.map((admin) => _buildMemberTile(admin, showRole: true)),
        ],
      ),
    );
  }

  Widget _buildMemberTile(GroupMember member, {bool showRole = false}) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: kDarkGrey,
        child: Text(
          member.displayName.isNotEmpty
              ? member.displayName[0].toUpperCase()
              : '?',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
      title: Text(
        member.displayName,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 13,
        ),
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
      case MemberRole.helper:
        label = 'Helper';
        color = const Color(0xFF14B8A6);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
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
