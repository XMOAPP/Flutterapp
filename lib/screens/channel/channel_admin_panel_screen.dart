import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/channel_service.dart';
import '../../models/channel_models.dart';

/// Channel Admin Panel - Manage channel admins and permissions
class ChannelAdminPanelScreen extends StatefulWidget {
  final Room room;

  const ChannelAdminPanelScreen({super.key, required this.room});

  @override
  State<ChannelAdminPanelScreen> createState() => _ChannelAdminPanelScreenState();
}

class _ChannelAdminPanelScreenState extends State<ChannelAdminPanelScreen> {
  late ChannelService _channelService;
  List<ChannelAdmin> _admins = [];
  List<ChannelSubscriber> _subscribers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _channelService = ChannelService(matrixProvider.service);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final admins = await _channelService.getAdmins(widget.room.id);
      final allSubscribers = await _channelService.getSubscribers(widget.room.id);
      final regularSubscribers = allSubscribers.where((s) => !s.isAdmin).toList();

      if (mounted) {
        setState(() {
          _admins = admins;
          _subscribers = regularSubscribers;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[ChannelAdminPanel] Error loading data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showPromoteDialog(ChannelSubscriber subscriber) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Promote ${subscriber.displayName}', style: GoogleFonts.inter(color: kWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select admin role:',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildRoleOption(ctx, 'Moderator', 'Can post and delete messages', 50, subscriber),
            _buildRoleOption(ctx, 'Admin', 'Can manage channel and edit info', 75, subscriber),
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

  Widget _buildRoleOption(BuildContext ctx, String title, String description, int powerLevel, ChannelSubscriber subscriber) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _promoteToLevel(subscriber, powerLevel);
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

  Future<void> _promoteToLevel(ChannelSubscriber subscriber, int powerLevel) async {
    try {
      final permissions = ChannelAdminPermissions.fromPowerLevel(powerLevel);
      await _channelService.promoteToAdmin(widget.room.id, subscriber.userId, permissions);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${subscriber.displayName} promoted successfully'),
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

  Future<void> _demoteAdmin(ChannelAdmin admin) async {
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
            child: Text('Demote', style: GoogleFonts.inter(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _channelService.demoteAdmin(widget.room.id, admin.userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${admin.displayName} demoted to subscriber'),
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

                  // Promote Subscribers
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Promote Subscribers',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_subscribers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'All subscribers are admins',
                        style: GoogleFonts.inter(color: kLightGrey),
                      ),
                    )
                  else
                    ..._subscribers.map((subscriber) => _buildSubscriberTile(subscriber)),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildAdminTile(ChannelAdmin admin) {
    final myUserId = context.read<MatrixProvider>().userId ?? '';
    final isMe = admin.userId == myUserId;
    final isOwner = admin.powerLevel >= 100;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: kDarkGrey,
        child: Text(
          admin.displayName.isNotEmpty ? admin.displayName[0].toUpperCase() : '?',
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: kLimeGreen.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: kLimeGreen, width: 1),
            ),
            child: Text(
              isOwner ? 'Owner' : 'Admin',
              style: GoogleFonts.inter(
                color: kLimeGreen,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        'Power Level: ${admin.powerLevel}',
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      trailing: !isMe && !isOwner
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.orange, size: 20),
              onPressed: () => _demoteAdmin(admin),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          : null,
    );
  }

  Widget _buildSubscriberTile(ChannelSubscriber subscriber) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: kDarkGrey,
        child: Text(
          subscriber.displayName.isNotEmpty ? subscriber.displayName[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
      title: Text(
        subscriber.displayName,
        style: GoogleFonts.inter(color: kWhite, fontSize: 13),
      ),
      subtitle: Text(
        subscriber.userId,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_moderator, color: kLimeGreen, size: 20),
        onPressed: () => _showPromoteDialog(subscriber),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }
}
