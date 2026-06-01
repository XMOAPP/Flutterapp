import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../../models/invite_link_models.dart';
import '../../services/matrix_service.dart';
import '../shared/invite_link_view.dart';

/// Invite Links Screen - Generate and share invite links for groups
class InviteLinksScreen extends StatefulWidget {
  final Room room;

  const InviteLinksScreen({super.key, required this.room});

  @override
  State<InviteLinksScreen> createState() => _InviteLinksScreenState();
}


class _InviteLinksScreenState extends State<InviteLinksScreen> {
  XmoInviteLink? _inviteLink;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadOrCreateInviteLink();
  }

  Future<void> _loadOrCreateInviteLink() async {
    setState(() => _loading = true);
    try {
      final service = MatrixService();
      final link = await service.getActiveInviteLink(widget.room.id) ??
          await service.generateTrackedInviteLink(widget.room.id);

      if (mounted) {
        setState(() {
          _inviteLink = link;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[InviteLinks] Error generating link: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generateInviteLink() async {
    setState(() => _loading = true);
    try {
      final link = await MatrixService().generateTrackedInviteLink(
        widget.room.id,
      );

      if (mounted) {
        setState(() {
          _inviteLink = link;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[InviteLinks] Error regenerating link: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to regenerate link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _revokeInviteLink() async {
    final link = _inviteLink;
    if (link == null) return;

    setState(() => _loading = true);
    try {
      await MatrixService().revokeInviteLink(widget.room.id, link.linkId);

      if (mounted) {
        setState(() {
          _inviteLink = null;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite link revoked'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('[InviteLinks] Error revoking link: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to revoke link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomName = MatrixService().getResolvedDisplayName(widget.room);
    return InviteLinkView(
      title: 'Share Group',
      roomName: roomName,
      roomType: 'group',
      icon: Icons.group,
      inviteLink: _inviteLink?.url,
      canRevoke: _inviteLink?.canBeUsed ?? false,
      loading: _loading,
      onBack: () => Navigator.pop(context),
      onRegenerate: _generateInviteLink,
      onRevoke: _revokeInviteLink,
    );
  }
}
