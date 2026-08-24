import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/story_models.dart';

void main() {
  group('direct-contact story audience', () {
    test('contacts and the legacy allUsers key include direct contacts', () {
      expect(
        canDirectContactViewStory(
          _story(privacy: StoryPrivacy.contacts),
          '@contact:xmo.test',
        ),
        isTrue,
      );
      expect(
        canDirectContactViewStory(
          _story(privacy: StoryPrivacy.allUsers),
          '@contact:xmo.test',
        ),
        isTrue,
      );
    });

    test('custom includes only selected direct contacts', () {
      final story = _story(
        privacy: StoryPrivacy.custom,
        customPrivacyList: const ['@selected:xmo.test'],
      );

      expect(canDirectContactViewStory(story, '@selected:xmo.test'), isTrue);
      expect(canDirectContactViewStory(story, '@other:xmo.test'), isFalse);
    });

    test('contactsExcept excludes selected direct contacts', () {
      final story = _story(
        privacy: StoryPrivacy.contactsExcept,
        customPrivacyList: const ['@hidden:xmo.test'],
      );

      expect(canDirectContactViewStory(story, '@hidden:xmo.test'), isFalse);
      expect(canDirectContactViewStory(story, '@visible:xmo.test'), isTrue);
    });
  });

  group('story viewed state', () {
    test('reports unviewed while any active story is unseen', () {
      final userStories = UserStories(
        userId: '@owner:xmo.test',
        userName: 'Owner',
        stories: [
          _story(id: 'viewed', viewedBy: const ['@viewer:xmo.test']),
          _story(id: 'unviewed'),
        ],
      );

      expect(userStories.allViewedBy('@viewer:xmo.test'), isFalse);
    });

    test('reports viewed when every active story is seen', () {
      final userStories = UserStories(
        userId: '@owner:xmo.test',
        userName: 'Owner',
        stories: [
          _story(id: 'one', viewedBy: const ['@viewer:xmo.test']),
          _story(id: 'two', viewedBy: const ['@viewer:xmo.test']),
        ],
      );

      expect(userStories.allViewedBy('@viewer:xmo.test'), isTrue);
    });
  });
}

Story _story({
  String id = 'story',
  StoryPrivacy privacy = StoryPrivacy.contacts,
  List<String>? customPrivacyList,
  List<String> viewedBy = const [],
}) {
  return Story(
    id: id,
    userId: '@owner:xmo.test',
    userName: 'Owner',
    mediaType: StoryMediaType.text,
    textContent: 'Story',
    createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    privacy: privacy,
    customPrivacyList: customPrivacyList,
    viewedBy: viewedBy,
  );
}
