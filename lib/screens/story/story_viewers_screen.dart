import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/story_models.dart';
import '../../providers/story_provider.dart';
import '../../theme.dart';

/// Draggable sheet showing the unique viewers of a story.
class StoryViewersSheet extends StatefulWidget {
  final String storyId;

  const StoryViewersSheet({
    super.key,
    required this.storyId,
  });

  @override
  State<StoryViewersSheet> createState() => _StoryViewersSheetState();
}

class _StoryViewersSheetState extends State<StoryViewersSheet> {
  List<StoryView> _viewers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadViewers();
  }

  Future<void> _loadViewers() async {
    try {
      final viewers =
          await context.read<StoryProvider>().getStoryViewers(widget.storyId);
      if (!mounted) return;
      setState(() {
        _viewers = viewers;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.58,
      minChildSize: 0.32,
      maxChildSize: 0.88,
      builder: (context, scrollController) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: kDarkerGrey,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: kMediumGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _loading ? 'Viewers' : 'Viewers (${_viewers.length})',
                        style: GoogleFonts.inter(
                          color: kWhite,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: kLightGrey),
                    ),
                  ],
                ),
              ),
              const Divider(color: kDarkGrey, height: 1),
              Expanded(child: _buildBody(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_loading) {
      return CustomScrollView(
        controller: scrollController,
        slivers: const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CircularProgressIndicator(color: kLimeGreen),
            ),
          ),
        ],
      );
    }

    if (_viewers.isEmpty) {
      return CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.visibility_off_outlined,
                    color: kMediumGrey,
                    size: 40,
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
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
      itemCount: _viewers.length,
      separatorBuilder: (_, __) => const Divider(
        color: kDarkGrey,
        height: 1,
        indent: 64,
      ),
      itemBuilder: (context, index) => _buildViewerTile(_viewers[index]),
    );
  }

  Widget _buildViewerTile(StoryView viewer) {
    final name = viewer.viewerName.trim();
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: kDarkGrey,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        name.isNotEmpty ? name : 'XMO user',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}
