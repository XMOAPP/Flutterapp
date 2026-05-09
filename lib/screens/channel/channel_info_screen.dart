import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/channel_service.dart';
import '../../services/matrix_service.dart';
import '../../models/channel_models.dart';
import '../../widgets/story/story_avatar.dart';
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
  List<ChannelAdmin> _admins = [];
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
      final admins = await _channelService.getAdmins(widget.room.id);
      final count = await _channelService.getSubscriberCount(widget.room.id);

      if (mounted) {
        setState(() {
          _subscribers = subscribers;
          _admins = admins;
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

  bool get _isAdmin => widget.room.ownPowerLevel >= 50;

  @override
  Widget build(BuildContext context) {
    final channelName = MatrixService().getResolvedDisplayName(widget.room);
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
          'Channel Info',
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
                  // Channel Header
                  _buildChannelHeader(channelName, _subscriberCount),

                  // Description
                  if (description.isNotEmpty) _buildDescription(description),

                  const SizedBox(height: 16),

                  // Actions
                  _buildActionButtons(),

                  const SizedBox(height: 8),

                  // Statistics (Admin only)
                  if (_isAdmin) _buildStatisticsSection(),

                  // Admins Section
                  if (_admins.isNotEmpty) _buildAdminsSection(),

                  // Subscribers Section
                  _buildSubscribersSection(),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildChannelHeader(String name, int subscriberCount) {
    return Container(
      padding: const EdgeInsets.all(24),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kLimeGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kLimeGreen, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.campaign, color: kLimeGreen, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'Channel',
                      style: GoogleFonts.inter(
                        color: kLimeGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Subscriber Count
          Text(
            '$subscriberCount subscriber${subscriberCount == 1 ? '' : 's'}',
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
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              icon: Icons.share_outlined,
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
          ),
          if (_isAdmin) const SizedBox(width: 8),
          if (_isAdmin)
            Expanded(
              child: _buildActionButton(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChannelSettingsScreen(room: widget.room),
                    ),
                  ).then((_) => _loadChannelData());
                },
              ),
            ),
          if (_isAdmin) const SizedBox(width: 8),
          if (_isAdmin)
            Expanded(
              child: _buildActionButton(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Admin Panel',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChannelAdminPanelScreen(room: widget.room),
                    ),
                  ).then((_) => _loadChannelData());
                },
              ),
            ),
          if (_isAdmin) const SizedBox(width: 8),
          if (_isAdmin)
            Expanded(
              child: _buildActionButton(
                icon: Icons.bar_chart_outlined,
                label: 'Statistics',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChannelStatisticsScreen(room: widget.room),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
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
    );
  }

  Widget _buildStatisticsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: kLimeGreen, size: 18),
              const SizedBox(width: 8),
              Text(
                'Quick Stats',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('Subscribers', '$_subscriberCount'),
              ),
              Expanded(
                child: _buildStatItem('Admins', '${_admins.length}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 11,
          ),
        ),
      ],
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          ..._admins.take(3).map((admin) => _buildAdminTile(admin)),
          if (_admins.length > 3)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'and ${_admins.length - 3} more...',
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

  Widget _buildSubscribersSection() {
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.people_outline, color: kLimeGreen, size: 20),
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
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: kLightGrey, size: 18),
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
          ..._subscribers.take(3).map((subscriber) => _buildSubscriberTile(subscriber)),
          if (_subscribers.length > 3)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'and ${_subscribers.length - 3} more...',
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

  Widget _buildAdminTile(ChannelAdmin admin) {
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
      title: Text(
        admin.displayName,
        style: GoogleFonts.inter(color: kWhite, fontSize: 13),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: kLimeGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: kLimeGreen, width: 1),
        ),
        child: Text(
          'Admin',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
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
          subscriber.displayName.isNotEmpty
              ? subscriber.displayName[0].toUpperCase()
              : '?',
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
    );
  }
}
