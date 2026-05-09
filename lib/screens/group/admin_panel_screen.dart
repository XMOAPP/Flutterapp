import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/group_service.dart';
import '../../models/group_models.dart';
import 'admin_log_screen.dart';

/// Admin Panel Screen - Manage admins and permissions
class AdminPanelScreen extends StatefulWidget {
  final Room room;

  const AdminPanelScreen({super.key, required this.room});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late GroupService _groupService;
  List<GroupMember> _admins = [];
  List<GroupMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _groupService = GroupService(matrixProvider.service);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final allMembers = await _groupService.getGroupMembers(widget.room.id);
      final admins = allMembers.where((m) => m.powerLevel >= 25).toList();
      final regularMembers =
          allMembers.where((m) => m.powerLevel < 25).toList();

      if (mounted) {
        setState(() {
          _admins = admins;
          _members = regularMembers;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[AdminPanel] Error loading data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showPromoteDialog(GroupMember member) {
    if (!GroupService.canManageAdmins(widget.room.ownPowerLevel)) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Promote ${member.displayName}',
            style: GoogleFonts.inter(color: kWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select admin role:',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildRoleOption(
              ctx,
              'Helper',
              'Can invite members and pin messages',
              25,
              member,
            ),
            _buildRoleOption(
              ctx,
              'Moderator',
              'Can kick, ban, and delete messages',
              50,
              member,
            ),
            _buildRoleOption(
              ctx,
              'Admin',
              'Can manage members and edit group info',
              75,
              member,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleOption(BuildContext ctx, String title, String description,
      int powerLevel, GroupMember member) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _promoteToLevel(member, powerLevel);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: kDarkGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kMediumGrey),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: kWhite,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promoteToLevel(GroupMember member, int powerLevel) async {
    try {
      if (!GroupService.canManageAdmins(widget.room.ownPowerLevel)) {
        throw Exception('Only owners can promote admins.');
      }

      final permissions = AdminPermissions(
        canAddMembers: true,
        canRemoveMembers: powerLevel >= 50,
        canBanMembers: powerLevel >= 50,
        canDeleteMessages: powerLevel >= 50,
        canPinMessages: true,
        canEditGroupInfo: powerLevel >= 75,
        canManageAdmins: false,
        canInviteUsers: true,
        canChangePermissions: false,
      );

      await _groupService.promoteToAdmin(
          widget.room.id, member.userId, permissions);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.displayName} promoted successfully'),
            backgroundColor: kLimeGreen,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to promote: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _demoteAdmin(GroupMember admin) async {
    if (!GroupService.canManageAdmins(widget.room.ownPowerLevel)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Demote Admin?', style: GoogleFonts.inter(color: kWhite)),
        content: Text(
          'Remove ${admin.displayName} from admin role?',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('Demote', style: GoogleFonts.inter(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _groupService.demoteAdmin(widget.room.id, admin.userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${admin.displayName} demoted to member'),
            backgroundColor: kLimeGreen,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to demote: $e'),
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
          'Admin Panel',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: kLimeGreen),
            tooltip: 'Admin log',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminLogScreen(room: widget.room),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Admins
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Current Admins (${_admins.length})',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_admins.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'No admins yet',
                        style: GoogleFonts.inter(color: kLightGrey),
                      ),
                    )
                  else
                    ..._admins.map((admin) => _buildAdminTile(admin)),

                  const SizedBox(height: 24),

                  // Promote Members
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Promote Members',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'All members are admins',
                        style: GoogleFonts.inter(color: kLightGrey),
                      ),
                    )
                  else
                    ..._members.map((member) => _buildMemberTile(member)),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildAdminTile(GroupMember admin) {
    final myUserId = context.read<MatrixProvider>().userId ?? '';
    final isMe = admin.userId == myUserId;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: kDarkGrey,
        child: Text(
          admin.displayName.isNotEmpty
              ? admin.displayName[0].toUpperCase()
              : '?',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              admin.displayName + (isMe ? ' (You)' : ''),
              style: GoogleFonts.inter(color: kWhite, fontSize: 13),
            ),
          ),
          _buildRoleBadge(admin.role),
        ],
      ),
      subtitle: Text(
        'Power Level: ${admin.powerLevel}',
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      trailing: !isMe && admin.role != MemberRole.owner
          ? IconButton(
              icon: Icon(
                Icons.remove_circle_outline,
                color: GroupService.canManageAdmins(widget.room.ownPowerLevel)
                    ? Colors.orange
                    : kLightGrey,
                size: 20,
              ),
              onPressed: GroupService.canManageAdmins(widget.room.ownPowerLevel)
                  ? () => _demoteAdmin(admin)
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          : null,
    );
  }

  Widget _buildMemberTile(GroupMember member) {
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
        style: GoogleFonts.inter(color: kWhite, fontSize: 13),
      ),
      subtitle: Text(
        member.userId,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.add_moderator,
          color: GroupService.canManageAdmins(widget.room.ownPowerLevel)
              ? kLimeGreen
              : kLightGrey,
          size: 20,
        ),
        onPressed: GroupService.canManageAdmins(widget.room.ownPowerLevel)
            ? () => _showPromoteDialog(member)
            : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
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
      case MemberRole.helper:
        label = 'Helper';
        color = const Color(0xFF14B8A6);
        break;
      case MemberRole.restricted:
        label = 'Restricted';
        color = Colors.orange;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
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
}
