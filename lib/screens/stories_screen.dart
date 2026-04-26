import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/data_models.dart';

class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stories = MockData.stories;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent circles row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'RECENT',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          SizedBox(
            height: 105,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: stories.length,
              itemBuilder: (context, index) {
                final story = stories[index];
                return _StoryCircle(story: story);
              },
            ),
          ),
          const SizedBox(height: 16),
          // 3-column grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 0.62,
              ),
              itemCount: stories.length,
              itemBuilder: (context, index) {
                return _StoryGridTile(story: stories[index]);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  final StoryModel story;

  const _StoryCircle({required this.story});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring: gradient for "Your Story", dark grey for others
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: story.isYourStory
                      ? const LinearGradient(
                          begin: Alignment.bottomLeft,
                          end: Alignment.topCenter,
                          colors: [
                            Color(0xFF2DB55D), // bright green (bottom)
                            Color(0xFF1565C0), // dark blue (top)
                          ],
                        )
                      : const LinearGradient(
                          colors: [
                            Color(0xFF9E9E9E),
                            Color(0xFF9E9E9E),
                          ],
                        ),
                ),
              ),
              // Black gap ring
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: kBlack,
                ),
              ),
              CircleAvatar(
                radius: 28,
                backgroundColor: kDarkGrey,
                backgroundImage: NetworkImage(
                  story.profileImageUrl ?? story.backgroundImageUrl,
                ),
              ),
              if (story.isYourStory)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      shape: BoxShape.circle,
                      border: Border.all(color: kBlack, width: 1.5),
                    ),
                    child: const Icon(Icons.add, color: kWhite, size: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            story.name,
            style: GoogleFonts.inter(color: kWhite, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StoryGridTile extends StatelessWidget {
  final StoryModel story;

  const _StoryGridTile({required this.story});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            story.backgroundImageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: kDarkGrey,
              child: const Icon(Icons.image, color: kLightGrey),
            ),
          ),
          // Dark gradient at top
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0xAA000000), Colors.transparent],
              ),
            ),
          ),
          // Avatar + name at top-left
          Positioned(
            top: 8,
            left: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Hollow gradient ring
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (Rect bounds) {
                        return story.isYourStory
                            ? const LinearGradient(
                                begin: Alignment.bottomLeft,
                                end: Alignment.topCenter,
                                colors: [
                                  Color(0xFF2DB55D), // bright green
                                  Color(0xFF1565C0), // dark blue
                                ],
                              ).createShader(bounds)
                            : const LinearGradient(
                                colors: [
                                  Color(0xFF9E9E9E),
                                  Color(0xFF9E9E9E),
                                ],
                              ).createShader(bounds);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: kDarkGrey,
                      backgroundImage: NetworkImage(
                        story.profileImageUrl ?? story.backgroundImageUrl,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  story.name,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      const Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
