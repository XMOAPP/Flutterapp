import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/story_provider.dart';
import '../../providers/matrix_provider.dart';
import '../../screens/story/story_creator_screen.dart';
import '../../screens/story/story_viewer_screen.dart';
import 'story_ring.dart';

/// Horizontal scrollable list of stories
class StoryList extends StatelessWidget {
  const StoryList({super.key});

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

        // Always show at least the "Add Story" button
        return Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount:
                1 + contactStories.length, // 1 for "Add Story" or "My Story"
            itemBuilder: (context, index) {
              // First item: Add Story or My Story
              if (index == 0) {
                if (hasMyStories) {
                  // Show my story
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: StoryRing(
                      userName: matrixProvider.displayName ?? 'You',
                      avatarUrl: matrixProvider.avatarUrl,
                      isMyStory: true,
                      hasUnviewedStories: true,
                      previewStory: myLatestStory.isNotEmpty
                          ? myLatestStory.last
                          : null,
                      storyCount: myLatestStory.length,
                      viewedCount: 0,
                      onAddStory: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StoryCreatorScreen(),
                          ),
                        );
                      },
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoryViewerScreen(
                              initialUserIndex: -1, // -1 indicates my story
                              allUserStories: [
                                ...storyProvider.myStories
                                    .map((s) => s.userId)
                                    .toSet(),
                                ...contactStories.map((us) => us.userId),
                              ].toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                } else {
                  // Show add story button
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: AddStoryButton(
                      userName: matrixProvider.displayName ?? 'You',
                      avatarUrl: matrixProvider.avatarUrl,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StoryCreatorScreen(),
                          ),
                        );
                      },
                    ),
                  );
                }
              }

              // Contact stories
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
                  hasUnviewedStories: storyProvider.hasUnviewedStories(
                    userStories.userId,
                    myUserId,
                  ),
                  previewStory: userStories.latestStory,
                  storyCount: activeStories.length,
                  viewedCount: viewedCount,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StoryViewerScreen(
                          initialUserIndex: index - 1,
                          allUserStories: contactStories
                              .map((us) => us.userId)
                              .toList(),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
