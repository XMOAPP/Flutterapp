import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/channel_service.dart';
import '../../models/channel_models.dart';

/// Channel Statistics Screen - View channel analytics (Admin only)
class ChannelStatisticsScreen extends StatefulWidget {
  final Room room;

  const ChannelStatisticsScreen({super.key, required this.room});

  @override
  State<ChannelStatisticsScreen> createState() => _ChannelStatisticsScreenState();
}

class _ChannelStatisticsScreenState extends State<ChannelStatisticsScreen> {
  late ChannelService _channelService;
  ChannelStatistics? _statistics;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _channelService = ChannelService(matrixProvider.service);
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() => _loading = true);
    try {
      final stats = await _channelService.getStatistics(widget.room.id);

      if (mounted) {
        setState(() {
          _statistics = stats;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[ChannelStatistics] Error loading statistics: $e');
      if (mounted) {
        setState(() => _loading = false);
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
          'Channel Statistics',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : _statistics == null
              ? Center(
                  child: Text(
                    'No statistics available',
                    style: GoogleFonts.inter(color: kLightGrey),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overview Stats
                      _buildOverviewSection(),
                      const SizedBox(height: 16),

                      // Post Activity
                      _buildPostActivitySection(),
                      const SizedBox(height: 16),

                      // Channel Info
                      _buildChannelInfoSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOverviewSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: kLimeGreen, size: 18),
              const SizedBox(width: 10),
              Text(
                'Overview',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Subscribers',
                  '${_statistics!.totalSubscribers}',
                  Icons.people_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Total Posts',
                  '${_statistics!.totalPosts}',
                  Icons.article_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPostActivitySection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: kLimeGreen, size: 18),
              const SizedBox(width: 10),
              Text(
                'Post Activity',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildActivityRow('Last 24 hours', '${_statistics!.postsLast24h} posts'),
          const SizedBox(height: 12),
          _buildActivityRow('Last 7 days', '${_statistics!.postsLast7days} posts'),
          const SizedBox(height: 12),
          _buildActivityRow('Average views', '${_statistics!.averageViews} per post'),
        ],
      ),
    );
  }

  Widget _buildChannelInfoSection() {
    final createdDate = _statistics!.createdAt;
    final formattedDate = '${createdDate.day}/${createdDate.month}/${createdDate.year}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: kLimeGreen, size: 18),
              const SizedBox(width: 10),
              Text(
                'Channel Info',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRow('Created on', formattedDate),
          const SizedBox(height: 12),
          _buildInfoRow('Channel type', widget.room.joinRules == JoinRules.public ? 'Public' : 'Private'),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: kLimeGreen, size: 26),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.inter(
              color: kWhite,
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
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActivityRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
