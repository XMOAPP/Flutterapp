import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../models/group_models.dart';

/// Mention autocomplete widget that shows @username suggestions
class MentionAutocomplete extends StatelessWidget {
  final List<GroupMember> members;
  final String query;
  final Function(GroupMember) onMemberSelected;

  const MentionAutocomplete({
    super.key,
    required this.members,
    required this.query,
    required this.onMemberSelected,
  });

  List<GroupMember> get _filteredMembers {
    if (query.isEmpty) return [];
    
    final lowerQuery = query.toLowerCase();
    return members.where((member) {
      final displayName = member.displayName.toLowerCase();
      final userId = member.userId.toLowerCase();
      return displayName.contains(lowerQuery) || userId.contains(lowerQuery);
    }).take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMembers;
    
    if (filtered.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: const BoxDecoration(
        color: kDarkerGrey,
        border: Border(
          top: BorderSide(color: kMediumGrey, width: 1),
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final member = filtered[index];
          return _buildMemberTile(member);
        },
      ),
    );
  }

  Widget _buildMemberTile(GroupMember member) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: kDarkGrey,
        child: Text(
          member.displayName.isNotEmpty 
              ? member.displayName[0].toUpperCase() 
              : '?',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        member.displayName,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        member.userId,
        style: GoogleFonts.inter(
          color: kLightGrey,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _buildRoleBadge(member.role),
      onTap: () => onMemberSelected(member),
    );
  }

  Widget _buildRoleBadge(MemberRole role) {
    if (role == MemberRole.member) return const SizedBox.shrink();
    
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
