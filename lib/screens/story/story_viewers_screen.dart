import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../models/story_models.dart';
import '../../providers/story_provider.dart';

/// Screen showing who viewed a story
class StoryViewersScreen extends StatefulWidget {
  final String storyId;

  const StoryViewersScreen({
    super.key,
    required this.storyId,
  });

  @override
  State<StoryViewersScreen> createState() => _StoryViewersScreenState();
}

class _StoryViewersScreenState extends State<StoryViewersScreen> {
  List<StoryView> _viewers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadViewers();
  }

  Future<void> _loadViewers() async {
    setState(() => _loading = true);
    try {
      final storyProvider = context.read<StoryProvider>();
      final viewers = await storyProvider.getStoryViewers(widget.storyId);
      if (mounted) {
        setState(() {
          _viewers = viewers;
          _loading = false;
        });
      }
    } catch (e) {
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
          'Viewers',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: kLimeGreen),
            )
          : _viewers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.visibility_off,
                        color: kMediumGrey,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No views yet',
                        style: GoogleFonts.inter(
                          color: kLightGrey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _viewers.length,
                  itemBuilder: (context, index) {
                    final viewer = _viewers[index];
                    return _buildViewerTile(viewer);
                  },
                ),
    );
  }

  Widget _buildViewerTile(StoryView viewer) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: kLimeGreen,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            viewer.viewerName.isNotEmpty
                ? viewer.viewerName[0].toUpperCase()
                : '?',
            style: GoogleFonts.inter(
              color: kBlack,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(
        viewer.viewerName,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _formatTimeAgo(viewer.viewedAt),
        style: GoogleFonts.inter(
          color: kLightGrey,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
