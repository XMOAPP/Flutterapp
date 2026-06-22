import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/story_models.dart';
import '../../providers/matrix_provider.dart';
import '../../theme.dart';
import 'story_avatar.dart';
import 'story_video_thumbnail.dart';

/// Story Ring Widget - Circular avatar with gradient border
class StoryRing extends StatelessWidget {
  final String userName;
  final String? avatarUrl;
  final bool hasUnviewedStories;
  final bool isMyStory;
  final VoidCallback onTap;
  final double size;
  final Story? previewStory;
  final int storyCount;
  final int viewedCount;
  final VoidCallback? onAddStory;

  const StoryRing({
    super.key,
    required this.userName,
    this.avatarUrl,
    this.hasUnviewedStories = false,
    this.isMyStory = false,
    required this.onTap,
    this.size = 64,
    this.previewStory,
    this.storyCount = 1,
    this.viewedCount = 0,
    this.onAddStory,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Story ring with avatar
          Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                painter: _SegmentedStoryRingPainter(
                  storyCount: storyCount,
                  viewedCount: viewedCount,
                  hasUnviewedStories: hasUnviewedStories,
                  isMyStory: isMyStory,
                ),
                child: Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: kBlack,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: _buildRingContent(context),
                  ),
                ),
              ),
              if (onAddStory != null)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: onAddStory,
                    child: Container(
                      width: size * 0.3,
                      height: size * 0.3,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1686D9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.add,
                        color: kWhite,
                        size: size * 0.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // User name
          SizedBox(
            width: size + 8,
            child: Text(
              isMyStory ? 'Your story' : userName,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRingContent(BuildContext context) {
    final story = previewStory;
    if (story == null) {
      return StoryAvatar(
        userName: userName,
        avatarUrl: avatarUrl,
        size: size - 9,
      );
    }

    final contentSize = size - 9;
    if (_isVideoStory(story)) {
      return ClipOval(
        child: StoryVideoThumbnail(
          story: story,
          fallback: storyVideoFallback(
            width: contentSize,
            height: contentSize,
          ),
          playIcon: const SizedBox.shrink(),
        ),
      );
    }

    if (_isImageStory(story)) {
      return Consumer<MatrixProvider>(
        builder: (context, matrixProvider, _) {
          final mediaRequest = matrixProvider.service.getMediaRequest(
            story.mediaUrl,
            width: 180,
            height: 180,
          );
          if (mediaRequest == null) {
            return _buildStoryTextFallback(contentSize, story);
          }
          return ClipOval(
            child: Image.network(
              mediaRequest.uri.toString(),
              headers: mediaRequest.headers,
              width: contentSize,
              height: contentSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _buildStoryTextFallback(contentSize, story),
            ),
          );
        },
      );
    }

    return _buildStoryTextFallback(contentSize, story);
  }

  bool _isVideoStory(Story story) {
    final mimeType = story.mediaMimeType?.toLowerCase() ?? '';
    return story.mediaUrl != null &&
        (story.mediaType == StoryMediaType.video ||
            mimeType.startsWith('video/') ||
            story.thumbnailUrl != null);
  }

  bool _isImageStory(Story story) {
    final mimeType = story.mediaMimeType?.toLowerCase() ?? '';
    return story.mediaUrl != null &&
        story.mediaType == StoryMediaType.image &&
        !mimeType.startsWith('video/') &&
        story.thumbnailUrl == null;
  }

  Widget _buildStoryTextFallback(double contentSize, Story story) {
    final text = (story.textContent ?? story.caption ?? userName).trim();
    final displayText = text.isNotEmpty ? text : userName;

    return Container(
      width: contentSize,
      height: contentSize,
      decoration: const BoxDecoration(
        color: kDarkerGrey,
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(10),
      child: Center(
        child: Text(
          displayText,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: contentSize * 0.17,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _SegmentedStoryRingPainter extends CustomPainter {
  final int storyCount;
  final int viewedCount;
  final bool hasUnviewedStories;
  final bool isMyStory;

  _SegmentedStoryRingPainter({
    required this.storyCount,
    required this.viewedCount,
    required this.hasUnviewedStories,
    required this.isMyStory,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final segmentCount = isMyStory ? 1 : storyCount.clamp(1, 24);
    final strokeWidth = segmentCount == 1 ? 2.6 : 3.0;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gap = segmentCount == 1 ? 0.0 : _gapForCount(segmentCount);
    final segmentSweep = ((math.pi * 2) - (gap * segmentCount)) / segmentCount;
    const startOffset = -math.pi / 2;

    for (var i = 0; i < segmentCount; i++) {
      final start = startOffset + (i * (segmentSweep + gap));
      final isViewed = i < viewedCount;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = segmentCount == 1 ? StrokeCap.round : StrokeCap.butt
        ..shader = isMyStory
            ? const SweepGradient(
                colors: [
                  Color(0xFF1686D9),
                  Color(0xFF20D7A3),
                  Color(0xFF1686D9),
                ],
                stops: [0.0, 0.55, 1.0],
                transform: GradientRotation(-math.pi / 2),
              ).createShader(rect)
            : null
        ..color = _segmentColor(
          index: i,
          segmentCount: segmentCount,
          isViewed: isViewed,
        );

      canvas.drawArc(rect, start, segmentSweep, false, paint);
    }
  }

  double _gapForCount(int count) {
    if (count <= 3) return 0.16;
    if (count <= 8) return 0.11;
    return 0.075;
  }

  Color _segmentColor({
    required int index,
    required int segmentCount,
    required bool isViewed,
  }) {
    if (!isMyStory) {
      return const Color(0xFF8A8A8A);
    }

    if (isViewed || !hasUnviewedStories) {
      return const Color(0xFF8A8A8A);
    }

    if (segmentCount <= 1) return const Color(0xFF1686D9);
    final t = index / (segmentCount - 1);
    return Color.lerp(
          const Color(0xFF20D7A3),
          const Color(0xFF1686D9),
          t,
        ) ??
        const Color(0xFF1686D9);
  }

  @override
  bool shouldRepaint(covariant _SegmentedStoryRingPainter oldDelegate) {
    return oldDelegate.storyCount != storyCount ||
        oldDelegate.viewedCount != viewedCount ||
        oldDelegate.hasUnviewedStories != hasUnviewedStories ||
        oldDelegate.isMyStory != isMyStory;
  }
}

/// Add Story Button - Special ring for creating new story
class AddStoryButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final String userName;
  final String? avatarUrl;

  const AddStoryButton({
    super.key,
    required this.onTap,
    this.size = 64,
    this.userName = 'You',
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Add button
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kMediumGrey, width: 2),
            ),
            child: Stack(
              children: [
                // Avatar placeholder
                Container(
                  margin: const EdgeInsets.all(2.5),
                  child: StoryAvatar(
                    userName: userName,
                    avatarUrl: avatarUrl,
                    size: size - 5,
                    backgroundColor: const Color(0xFF2C2C2E),
                    textColor: kWhite,
                    fallbackIcon: Icons.person,
                  ),
                ),
                // Plus icon
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: size * 0.3,
                    height: size * 0.3,
                    decoration: const BoxDecoration(
                      color: kLimeGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.add,
                      color: kBlack,
                      size: size * 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Label
          SizedBox(
            width: size + 8,
            child: Text(
              'Add story',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
