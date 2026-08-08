import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/channel_service.dart';
import '../../services/matrix_service.dart';
import '../../services/report_service.dart';
import '../../models/report_models.dart';
import '../../models/channel_models.dart';
import '../../widgets/incoming_call_fullscreen_scope.dart';
import '../../widgets/story/story_avatar.dart';
import '../../widgets/report_sheet.dart';
import '../direct_chat/shared_media_screen.dart';
import 'channel_settings_screen.dart';
import 'subscriber_list_screen.dart';
import 'channel_admin_panel_screen.dart';
import 'channel_invite_screen.dart';
import 'channel_statistics_screen.dart';

/// Channel Info Screen - Shows channel details, subscribers, admins, and statistics
class ChannelInfoScreen extends StatefulWidget {
  final Room room;

  const ChannelInfoScreen({super.key, required this.room});

  @override
  State<ChannelInfoScreen> createState() => _ChannelInfoScreenState();
}

class _ChannelInfoScreenState extends State<ChannelInfoScreen> {
  late ChannelService _channelService;
  List<ChannelSubscriber> _subscribers = [];
  int _subscriberCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _channelService = ChannelService(matrixProvider.service);
    _loadChannelData();
  }

  Future<void> _loadChannelData() async {
    setState(() => _loading = true);
    try {
      final subscribers = await _channelService.getSubscribers(widget.room.id);
      final count = await _channelService.getSubscriberCount(widget.room.id);

      if (mounted) {
        setState(() {
          _subscribers = subscribers;
          _subscriberCount = count;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[ChannelInfo] Error loading data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool get _isAdmin => widget.room.ownPowerLevel >= PowerLevel.moderator;

  @override
  Widget build(BuildContext context) {
    final channelName = MatrixService().getResolvedDisplayName(widget.room);
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
            'Channel Info',
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
                    // Channel Header
                    _buildChannelHeader(channelName, _subscriberCount),

                    // Description
                    if (description.isNotEmpty) _buildDescription(description),

                    const SizedBox(height: 16),

                    // Actions
                    _buildActionButtons(),

                    const SizedBox(height: 8),

                    // Subscribers Section
                    _buildSubscribersSection(),

                    const SizedBox(height: 8),

                    _buildSharedMediaSection(),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildChannelHeader(String name, int subscriberCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        children: [
          // Channel Avatar
          StoryAvatar(
            userName: name,
            avatarUrl: widget.room.avatar?.toString(),
            size: 100,
            fallbackIcon: Icons.campaign,
          ),
          const SizedBox(height: 16),

          // Channel Name
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

          // Subscriber Count
          Text(
            '$subscriberCount subscriber${subscriberCount == 1 ? '' : 's'}',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    if (!_isAdmin) {
      return [
        _buildMenuItem(
          value: 'report',
          icon: Icons.flag_outlined,
          label: 'Report Channel',
          destructive: true,
        ),
        _buildMenuItem(
          value: 'leave',
          icon: Icons.logout,
          label: 'Leave Channel',
          destructive: true,
        ),
      ];
    }

    return [
      _buildMenuItem(value: 'live', icon: Icons.live_tv, label: 'Live Stream'),
      _buildMenuItem(value: 'edit', icon: Icons.edit, label: 'Edit Channel'),
      _buildMenuItem(
        value: 'delete',
        icon: Icons.delete,
        label: 'Delete Channel',
        destructive: true,
      ),
      _buildMenuItem(
        value: 'report',
        icon: Icons.flag_outlined,
        label: 'Report Channel',
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

  void _handleMenuAction(String action) {
    switch (action) {
      case 'delete':
        _confirmDeleteChannel();
        break;
      case 'leave':
        _confirmLeaveChannel();
        break;
      case 'live':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live stream is not available yet'),
            backgroundColor: kLimeGreen,
          ),
        );
        break;
      case 'edit':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChannelSettingsScreen(room: widget.room),
          ),
        ).then((_) => _loadChannelData());
        break;
      case 'report':
        _reportChannel();
        break;
    }
  }

  Future<void> _reportChannel() async {
    final service = context.read<MatrixProvider>().service;
    final submitted = await showXmoReportSheet(
      context: context,
      reportService: ReportService(service),
      targetType: XmoReportTargetType.channel,
      contextType: XmoReportContextType.channel,
      title: 'Report channel',
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
  }

  Future<void> _confirmLeaveChannel() async {
    final confirmed = await _confirmAction(
      title: 'Leave Channel?',
      message: 'Leave this channel?',
      actionLabel: 'Leave',
    );
    if (confirmed != true) return;

    try {
      await widget.room.leave();
      if (!mounted) return;
      final provider = context.read<MatrixProvider>();
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
          content: Text('Failed to leave channel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteChannel() async {
    final confirmed = await _confirmAction(
      title: 'Delete Channel?',
      message: 'Delete this channel for subscribers you can remove?',
      actionLabel: 'Delete',
    );
    if (confirmed != true) return;

    try {
      await _channelService.deleteChannel(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete channel: $e'),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 24) / 4;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildActionButton(
                width: itemWidth,
                icon: Icons.share,
                label: 'Share Link',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChannelInviteScreen(room: widget.room),
                    ),
                  );
                },
              ),
              if (_isAdmin)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.settings,
                  label: 'Settings',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChannelSettingsScreen(room: widget.room),
                      ),
                    ).then((_) => _loadChannelData());
                  },
                ),
              if (_isAdmin)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.admin_panel_settings,
                  label: 'Admin Panel',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChannelAdminPanelScreen(room: widget.room),
                      ),
                    ).then((_) => _loadChannelData());
                  },
                ),
              if (_isAdmin)
                _buildActionButton(
                  width: itemWidth,
                  icon: Icons.bar_chart,
                  label: 'Statistics',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChannelStatisticsScreen(room: widget.room),
                      ),
                    );
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

  Widget _buildSubscribersSection() {
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
            leading: const Icon(Icons.people, color: kLimeGreen, size: 20),
            title: Text(
              'Subscribers',
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
                  '$_subscriberCount',
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubscriberListScreen(
                    room: widget.room,
                    subscribers: _subscribers,
                  ),
                ),
              ).then((_) => _loadChannelData());
            },
          ),
          // Show first 3 subscribers
          ..._subscribers
              .take(3)
              .map((subscriber) => _buildSubscriberTile(subscriber)),
          if (_subscribers.length > 3)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'and ${_subscribers.length - 3} more...',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubscriberTile(ChannelSubscriber subscriber) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      minLeadingWidth: 46,
      horizontalTitleGap: 12,
      leading: StoryAvatar(
        userName: subscriber.displayName,
        avatarUrl: subscriber.avatarUrl,
        size: 46,
      ),
      title: Text(
        subscriber.displayName,
        style: GoogleFonts.inter(color: kWhite, fontSize: 13),
      ),
      trailing: subscriber.isAdmin ? _buildAdminBadge() : null,
    );
  }

  Widget _buildAdminBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kLimeGreen.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Admin',
        style: GoogleFonts.inter(
          color: kLimeGreen,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
