import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/story_provider.dart';
import '../../providers/matrix_provider.dart';
import '../../models/story_models.dart';
import '../../widgets/story/story_avatar.dart';
import '../../widgets/story/story_ring.dart';
import '../../widgets/story/story_video_thumbnail.dart';
import '../story/story_creator_screen.dart';
import '../story/story_viewer_screen.dart';

/// Stories View - Shows when Stories tab is selected
class StoriesView extends StatelessWidget {
  const StoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryProvider, MatrixProvider>(
      builder: (context, storyProvider, matrixProvider, _) {
        final myUserId = matrixProvider.userId ?? '';
        final hasMyStories = storyProvider.hasMyStories;
        final myLatestStory =
            storyProvider.myStories.where((story) => !story.isExpired).toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final contactStories = storyProvider.contactStories;

        return CustomScrollView(
          slivers: [
            // Section: RECENT (Story Rings)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'RECENT',
                      style: GoogleFonts.inter(
                        color: kLightGrey,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: 1 + contactStories.length,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // My Story / Add Story
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: hasMyStories
                                ? StoryRing(
                                    userName:
                                        matrixProvider.displayName ?? 'You',
                                    avatarUrl: matrixProvider.avatarUrl,
                                    isMyStory: true,
                                    hasUnviewedStories: true,
                                    previewStory: myLatestStory.isNotEmpty
                                        ? myLatestStory.last
                                        : null,
                                    storyCount: myLatestStory.length,
                                    viewedCount: 0,
                                    onAddStory: () =>
                                        _openStoryCreator(context),
                                    onTap: () => _openMyStory(
                                      context,
                                      storyProvider,
                                      contactStories,
                                    ),
                                  )
                                : AddStoryButton(
                                    userName:
                                        matrixProvider.displayName ?? 'You',
                                    avatarUrl: matrixProvider.avatarUrl,
                                    onTap: () => _openStoryCreator(context),
                                  ),
                          );
                        }

                        final userStories = contactStories[index - 1];
                        final activeStories = userStories.activeStories;
                        final viewedCount = activeStories
                            .where((story) => story.isViewedBy(myUserId))
                            .length;

                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: StoryRing(
                            userName: userStories.userName,
                            avatarUrl: userStories.userAvatarUrl,
                            hasUnviewedStories: storyProvider
                                .hasUnviewedStories(
                                  userStories.userId,
                                  myUserId,
                                ),
                            previewStory: userStories.latestStory,
                            storyCount: activeStories.length,
                            viewedCount: viewedCount,
                            onTap: () => _openStoryViewer(
                              context,
                              index - 1,
                              contactStories,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Section: Story Grid (if there are stories)
            if (hasMyStories || contactStories.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'ALL STORIES',
                    style: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = (constraints.crossAxisExtent / 120)
                        .floor()
                        .clamp(3, 4);
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (hasMyStories && index == 0) {
                            // My stories grid item
                            return _buildStoryGridItem(
                              context: context,
                              userStories: UserStories(
                                userId: myUserId,
                                userName: matrixProvider.displayName ?? 'Your',
                                userAvatarUrl: matrixProvider.avatarUrl,
                                stories: storyProvider.myStories,
                              ),
                              isMyStory: true,
                              onTap: () => _openMyStory(
                                context,
                                storyProvider,
                                contactStories,
                              ),
                            );
                          }

                          final contactIndex = hasMyStories ? index - 1 : index;
                          if (contactIndex >= contactStories.length) {
                            return null;
                          }

                          final userStories = contactStories[contactIndex];
                          return _buildStoryGridItem(
                            context: context,
                            userStories: userStories,
                            isMyStory: false,
                            onTap: () => _openStoryViewer(
                              context,
                              contactIndex,
                              contactStories,
                            ),
                          );
                        },
                        childCount:
                            (hasMyStories ? 1 : 0) + contactStories.length,
                      ),
                    );
                  },
                ),
              ),
            ] else
              // Empty state
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.auto_stories_outlined,
                        color: kMediumGrey,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No stories yet',
                        style: GoogleFonts.inter(
                          color: kLightGrey,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Share your moments with friends',
                        style: GoogleFonts.inter(
                          color: kMediumGrey,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _openStoryCreator(context),
                        icon: const Icon(Icons.add, color: kBlack, size: 20),
                        label: Text(
                          'Create Story',
                          style: GoogleFonts.inter(
                            color: kBlack,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kLimeGreen,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStoryGridItem({
    required BuildContext context,
    required UserStories userStories,
    required bool isMyStory,
    required VoidCallback onTap,
  }) {
    final latestStory = userStories.latestStory;
    if (latestStory == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: kDarkerGrey,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Story preview (image/video/text)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildStoryPreview(latestStory),
            ),

            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

            // User info
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: kWhite, width: 1.25),
                      shape: BoxShape.circle,
                    ),
                    child: StoryAvatar(
                      userName: userStories.userName,
                      avatarUrl: userStories.userAvatarUrl,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      userStories.userName,
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          const Shadow(color: Colors.black54, blurRadius: 4),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Story count (bottom)
            if (userStories.activeStories.length > 1)
              Positioned(
                bottom: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers, color: kWhite, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '${userStories.activeStories.length}',
                        style: GoogleFonts.inter(
                          color: kWhite,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryPreview(Story story) {
    // For text-only stories
    if (story.mediaType == StoryMediaType.text ||
        (story.mediaUrl == null && story.textContent != null)) {
      return _buildTextPreview(story);
    }

    // For video stories
    if (_isVideoStory(story)) {
      return StoryVideoThumbnail(
        story: story,
        loading: _buildLoadingPreview(),
        fallback: storyVideoFallback(),
        playIcon: const SizedBox.shrink(),
      );
    }

    // For image stories
    if (_isImageStory(story)) {
      return Consumer<MatrixProvider>(
        builder: (context, matrixProvider, _) {
          // Convert MXC URL to HTTP URL with thumbnail size
          final mediaRequest = matrixProvider.service.getMediaRequest(
            story.mediaUrl,
            width: 400,
            height: 600,
          );

          if (mediaRequest != null) {
            return Image.network(
              mediaRequest.uri.toString(),
              headers: mediaRequest.headers,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildTextPreview(story),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: kDarkerGrey,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: kLimeGreen,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
            );
          } else {
            return _buildTextPreview(story);
          }
        },
      );
    }

    // Fallback to text or caption
    return _buildTextPreview(story);
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

  Widget _buildLoadingPreview() {
    return Container(
      color: kDarkerGrey,
      child: const Center(
        child: CircularProgressIndicator(color: kLimeGreen, strokeWidth: 2),
      ),
    );
  }

  Widget _buildTextPreview(Story story) {
    final displayText = story.textContent ?? story.caption ?? 'Story';

    return Container(
      color: kDarkerGrey,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          displayText,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _openStoryCreator(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StoryCreatorScreen()),
    );
  }

  void _openMyStory(
    BuildContext context,
    StoryProvider storyProvider,
    List<UserStories> contactStories,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          initialUserIndex: -1,
          allUserStories: contactStories.map((us) => us.userId).toList(),
        ),
      ),
    );
  }

  void _openStoryViewer(
    BuildContext context,
    int userIndex,
    List<UserStories> contactStories,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          initialUserIndex: userIndex,
          allUserStories: contactStories.map((us) => us.userId).toList(),
        ),
      ),
    );
  }
}
