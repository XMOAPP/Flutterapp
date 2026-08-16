import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/group_service.dart';
import '../../models/group_models.dart';
import '../../widgets/story/story_avatar.dart';

/// Member List Screen - Shows all group members with search and actions
class MemberListScreen extends StatefulWidget {
  final Room room;
  final List<GroupMember> members;

  const MemberListScreen({
    super.key,
    required this.room,
    required this.members,
  });

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  final _searchCtrl = TextEditingController();
  late GroupService _groupService;
  List<GroupMember> _filteredMembers = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _groupService = GroupService(matrixProvider.service);
    _filteredMembers = widget.members;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterMembers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMembers = widget.members;
      } else {
        _filteredMembers = widget.members
            .where(
              (m) => m.displayName.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  bool get _canModerate =>
      GroupService.canModerateMembers(widget.room.ownPowerLevel.level);

  bool get _canManageAdmins =>
      GroupService.canManageAdmins(widget.room.ownPowerLevel.level);

  String get _myUserId => context.read<MatrixProvider>().userId ?? '';

  void _showMemberActions(GroupMember member) {
    if (member.userId == _myUserId) return; // Can't act on self
    if (!_canModerate && !_canManageAdmins) return;

    final canAct = GroupService.canActOnMember(
      actorPowerLevel: widget.room.ownPowerLevel.level,
      targetPowerLevel: member.powerLevel,
    );
    final canChangeAdmin = GroupService.canChangePowerLevel(
      actorPowerLevel: widget.room.ownPowerLevel.level,
      targetPowerLevel: member.powerLevel,
      newPowerLevel: member.powerLevel >= 50 ? 0 : 50,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: kDarkerGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canChangeAdmin)
              ListTile(
                leading: const Icon(
                  Icons.admin_panel_settings,
                  color: kLimeGreen,
                ),
                title: Text(
                  member.powerLevel >= 50
                      ? 'Demote from Admin'
                      : 'Promote to Moderator',
                  style: GoogleFonts.inter(color: kWhite),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleAdmin(member);
                },
              ),
            if (canAct)
              ListTile(
                leading: const Icon(Icons.person_remove, color: Colors.orange),
                title: Text(
                  'Remove from Group',
                  style: GoogleFonts.inter(color: Colors.orange),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeMember(member);
                },
              ),
            if (canAct)
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: Text(
                  'Ban Member',
                  style: GoogleFonts.inter(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _banMember(member);
                },
              ),
            if (canAct)
              ListTile(
                leading: Icon(
                  member.restriction == null
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  color: Colors.orange,
                ),
                title: Text(
                  member.restriction == null
                      ? 'Set Read-only'
                      : 'Remove Restriction',
                  style: GoogleFonts.inter(color: Colors.orange),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (member.restriction == null) {
                    _restrictReadOnly(member);
                  } else {
                    _removeRestriction(member);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAdmin(GroupMember member) async {
    setState(() => _loading = true);
    try {
      if (member.powerLevel >= 50) {
        // Demote
        await _groupService.demoteAdmin(widget.room.id, member.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${member.displayName} demoted to member'),
              backgroundColor: kLimeGreen,
            ),
          );
        }
      } else {
        // Promote
        final permissions = AdminPermissions(
          canAddMembers: true,
          canRemoveMembers: true,
          canBanMembers: true,
          canDeleteMessages: true,
          canPinMessages: true,
          canEditGroupInfo: false,
          canManageAdmins: false,
          canInviteUsers: true,
          canChangePermissions: false,
        );
        await _groupService.promoteToAdmin(
          widget.room.id,
          member.userId,
          permissions,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${member.displayName} promoted to admin'),
              backgroundColor: kLimeGreen,
            ),
          );
        }
      }
      // Refresh member list
      if (mounted) {
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeMember(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Remove Member?', style: GoogleFonts.inter(color: kWhite)),
        content: Text(
          'Remove ${member.displayName} from this group?',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: GoogleFonts.inter(color: Colors.orange),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _groupService.removeMember(widget.room.id, member.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.displayName} removed'),
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _banMember(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Ban Member?', style: GoogleFonts.inter(color: kWhite)),
        content: Text(
          'Ban ${member.displayName} from this group? They won\'t be able to rejoin.',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ban', style: GoogleFonts.inter(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _groupService.banMember(widget.room.id, member.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.displayName} banned'),
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restrictReadOnly(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Set Read-only?', style: GoogleFonts.inter(color: kWhite)),
        content: Text(
          '${member.displayName} will be able to read messages but not send new ones.',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Restrict',
              style: GoogleFonts.inter(color: Colors.orange),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _groupService.restrictMember(
        widget.room.id,
        MemberRestriction(
          userId: member.userId,
          type: RestrictionType.readOnly,
          reason: 'Set from member list',
          restrictedBy: _myUserId,
          restrictedAt: DateTime.now(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.displayName} set to read-only'),
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeRestriction(GroupMember member) async {
    setState(() => _loading = true);
    try {
      await _groupService.removeRestriction(widget.room.id, member.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restriction removed from ${member.displayName}'),
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
    } finally {
      if (mounted) setState(() => _loading = false);
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
          'Members (${_filteredMembers.length})',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: kWhite),
              decoration: InputDecoration(
                hintText: 'Search members...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: kLightGrey),
                filled: true,
                fillColor: const Color(0xFF2C2C2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _filterMembers,
            ),
          ),

          // Member List
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kLimeGreen),
                  )
                : ListView.builder(
                    itemCount: _filteredMembers.length,
                    itemBuilder: (_, i) =>
                        _buildMemberTile(_filteredMembers[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(GroupMember member) {
    final isMe = member.userId == _myUserId;

    return ListTile(
      leading: StoryAvatar(
        userName: member.displayName,
        avatarUrl: member.avatarUrl,
        size: 40,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              member.displayName + (isMe ? ' (You)' : ''),
              style: GoogleFonts.inter(color: kWhite),
            ),
          ),
          if (member.powerLevel >= 50) _buildRoleBadge(member.role),
          if (member.restriction != null) _buildRestrictedBadge(),
        ],
      ),
      onTap: (_canModerate || _canManageAdmins) && !isMe
          ? () => _showMemberActions(member)
          : null,
    );
  }

  Widget _buildRoleBadge(MemberRole role) {
    String label;
    Color color;

    switch (role) {
      case MemberRole.owner:
        label = 'Owner';
        color = const Color(0xFFFFD700);
        break;
      case MemberRole.admin:
        label = 'Admin';
        color = kLimeGreen;
        break;
      case MemberRole.moderator:
        label = 'Mod';
        color = const Color(0xFF3B82F6);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRestrictedBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange, width: 1),
      ),
      child: Text(
        'Read-only',
        style: GoogleFonts.inter(
          color: Colors.orange,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
