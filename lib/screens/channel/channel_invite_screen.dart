import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../models/invite_link_models.dart';
import '../../providers/matrix_provider.dart';
import '../../services/channel_service.dart';
import '../../services/matrix_service.dart';
import '../shared/invite_link_view.dart';

/// Channel Invite Screen - Generate and share invite links for channels
class ChannelInviteScreen extends StatefulWidget {
  final Room room;

  const ChannelInviteScreen({super.key, required this.room});

  @override
  State<ChannelInviteScreen> createState() => _ChannelInviteScreenState();
}

class _ChannelInviteScreenState extends State<ChannelInviteScreen> {
  late MatrixService _matrixService;
  late ChannelService _channelService;
  XmoInviteLink? _inviteLink;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _matrixService = matrixProvider.service;
    _channelService = ChannelService(_matrixService);
    _loadOrCreateInviteLink();
  }

  Future<void> _loadOrCreateInviteLink() async {
    setState(() => _loading = true);
    try {
      final link = await _matrixService.getActiveInviteLink(widget.room.id) ??
          await _matrixService.generateTrackedInviteLink(widget.room.id);

      if (mounted) {
        setState(() {
          _inviteLink = link;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[ChannelInvite] Error generating link: $e');
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
      final link = await _channelService.generateInviteLink(widget.room.id);

      if (mounted) {
        setState(() {
          _inviteLink = XmoInviteLink(
            linkId: link.linkId,
            url: link.url,
            roomId: link.channelId,
            createdAt: link.createdAt,
            expiresAt: link.expiresAt,
            usedCount: link.usedCount,
            createdBy: link.createdBy,
            isActive: link.isActive,
          );
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[ChannelInvite] Error regenerating link: $e');
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
      await _matrixService.revokeInviteLink(widget.room.id, link.linkId);

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
      debugPrint('[ChannelInvite] Error revoking link: $e');
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
    final roomName = _matrixService.getResolvedDisplayName(widget.room);
    return InviteLinkView(
      title: 'Share Channel',
      roomName: roomName,
      roomType: 'channel',
      icon: Icons.campaign,
      inviteLink: _inviteLink?.url,
      canRevoke: _inviteLink?.canBeUsed ?? false,
      loading: _loading,
      onBack: () => Navigator.pop(context),
      onRegenerate: _generateInviteLink,
      onRevoke: _revokeInviteLink,
    );
  }
}
