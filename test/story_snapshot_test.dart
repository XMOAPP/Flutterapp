import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/story_models.dart';

void main() {
  group('story snapshot ordering', () {
    test('rejects an older snapshot that contains fewer stories', () {
      final current = _snapshot(
        version: 300,
        storyTimes: const [100, 200, 300],
      );
      final incoming = _snapshot(version: 100, storyTimes: const [100]);

      expect(shouldReplaceStorySnapshot(current, incoming), isFalse);
    });

    test('accepts a newer snapshot with additional stories', () {
      final current = _snapshot(version: 100, storyTimes: const [100]);
      final incoming = _snapshot(
        version: 300,
        storyTimes: const [100, 200, 300],
      );

      expect(shouldReplaceStorySnapshot(current, incoming), isTrue);
    });

    test('accepts a newer empty snapshot when stories are deleted', () {
      final current = _snapshot(version: 100, storyTimes: const [100]);
      final incoming = _snapshot(version: 200, storyTimes: const []);

      expect(shouldReplaceStorySnapshot(current, incoming), isTrue);
    });

    test('rejects an ambiguous unversioned subset', () {
      final current = _snapshot(storyTimes: const [100, 200]);
      final incoming = _snapshot(storyTimes: const [100]);

      expect(shouldReplaceStorySnapshot(current, incoming), isFalse);
    });

    test('accepts an unversioned snapshot containing a newer story', () {
      final current = _snapshot(storyTimes: const [100]);
      final incoming = _snapshot(storyTimes: const [100, 200]);

      expect(shouldReplaceStorySnapshot(current, incoming), isTrue);
    });
  });
}

UserStories _snapshot({int? version, required List<int> storyTimes}) {
  return UserStories(
    userId: '@story-owner:xmo.test',
    userName: 'Story owner',
    snapshotUpdatedAt: version == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(version),
    stories: [
      for (final time in storyTimes)
        Story(
          id: 'story-$time',
          userId: '@story-owner:xmo.test',
          userName: 'Story owner',
          mediaType: StoryMediaType.text,
          textContent: 'Story $time',
          createdAt: DateTime.fromMillisecondsSinceEpoch(time),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
          privacy: StoryPrivacy.contacts,
        ),
    ],
  );
}
