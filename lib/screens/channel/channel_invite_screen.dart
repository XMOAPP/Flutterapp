import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../models/invite_link_models.dart';
import '../../providers/matrix_provider.dart';
import '../../services/invite_link_service.dart';
import '../../services/matrix_service.dart';
import '../../services/room_controls_service.dart';
import '../shared/invite_link_view.dart';

class ChannelInviteScreen extends StatefulWidget {
  const ChannelInviteScreen({super.key, required this.room});

  final Room room;

  @override
  State<ChannelInviteScreen> createState() => _ChannelInviteScreenState();
}

class _ChannelInviteScreenState extends State<ChannelInviteScreen> {
  late final MatrixService _matrixService;
  XmoInviteLink? _inviteLink;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _matrixService = context.read<MatrixProvider>().service;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadOrCreateInviteLink();
    });
  }

  Future<void> _loadOrCreateInviteLink() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final links = await InviteLinkService.instance.listInvites(
        _matrixService,
        widget.room.id,
      );
      final active = _firstUsable(links);
      final link = active ?? await _createWithJoinModeConfirmation();
      if (!mounted) return;
      setState(() => _inviteLink = link);
    } on InviteLinkException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Invite links are temporarily unavailable.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  XmoInviteLink? _firstUsable(List<XmoInviteLink> links) {
    for (final link in links) {
      if (link.canBeUsed) return link;
    }
    return null;
  }

  Future<XmoInviteLink?> _createWithJoinModeConfirmation() async {
    try {
      return await InviteLinkService.instance.createInvite(
        _matrixService,
        widget.room.id,
      );
    } on InviteLinkException catch (error) {
      if (error.statusCode != 409 ||
          !RoomControlsService.isPrivateEncrypted(widget.room) ||
          !mounted) {
        rethrow;
      }
      final enable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable join requests?'),
          content: const Text(
            'People with this link can request access. The channel remains private and encrypted, and an admin must approve each request.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (enable != true) return null;
      await RoomControlsService.setChannelJoinMode(
        widget.room,
        XmoJoinMode.request,
      );
      return InviteLinkService.instance.createInvite(
        _matrixService,
        widget.room.id,
      );
    }
  }

  Future<void> _generateInviteLink() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final link = await _createWithJoinModeConfirmation();
      if (!mounted || link == null) return;
      setState(() => _inviteLink = link);
    } on InviteLinkException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not create a new invite link.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revokeInviteLink() async {
    final link = _inviteLink;
    if (link == null || _loading) return;
    setState(() => _loading = true);
    try {
      await InviteLinkService.instance.revokeInvite(
        _matrixService,
        link.linkId,
      );
      if (!mounted) return;
      setState(() => _inviteLink = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite link disabled')));
    } on InviteLinkException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not disable the invite link.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return InviteLinkView(
      title: 'Share Channel',
      roomName: _matrixService.getResolvedDisplayName(widget.room),
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
