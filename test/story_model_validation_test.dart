import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/story_models.dart';

void main() {
  group('Story payload validation', () {
    test('accepts a legacy version-one text story', () {
      final story = Story.tryFromJson(_validTextStory()..remove('version'));

      expect(story, isNotNull);
      expect(story!.formatVersion, Story.currentFormatVersion);
      expect(story.toJson()['version'], Story.currentFormatVersion);
    });

    test('rejects unsupported versions', () {
      final story = Story.tryFromJson(
        _validTextStory()..['version'] = Story.currentFormatVersion + 1,
      );

      expect(story, isNull);
    });

    test('requires MXC media URLs for image and video stories', () {
      final payload = _validTextStory()
        ..['media_type'] = StoryMediaType.image.name
        ..['text_content'] = null
        ..['media_url'] = 'https://example.test/story.jpg';

      expect(Story.tryFromJson(payload), isNull);

      payload['media_url'] = 'mxc://xmo.test/story';
      expect(Story.tryFromJson(payload), isNotNull);
    });

    test('requires text content for text stories', () {
      final payload = _validTextStory()..['text_content'] = '   ';

      expect(Story.tryFromJson(payload), isNull);
    });

    test('rejects malformed and oversized fields without throwing', () {
      final malformed = _validTextStory()..['created_at'] = 'not-a-time';
      final oversized = _validTextStory()
        ..['caption'] = 'c' * (Story.maxCaptionLength + 1);

      expect(() => Story.tryFromJson(malformed), returnsNormally);
      expect(Story.tryFromJson(malformed), isNull);
      expect(Story.tryFromJson(oversized), isNull);
    });

    test('deduplicates bounded viewer and audience lists', () {
      final story = Story.tryFromJson(
        _validTextStory()
          ..['privacy'] = StoryPrivacy.custom.name
          ..['viewed_by'] = [
            '@viewer:xmo.test',
            '@viewer:xmo.test',
          ]
          ..['custom_privacy_list'] = [
            '@contact:xmo.test',
            '@contact:xmo.test',
          ],
      );

      expect(story, isNotNull);
      expect(story!.viewedBy, ['@viewer:xmo.test']);
      expect(story.customPrivacyList, ['@contact:xmo.test']);
    });
  });

  group('Story creation state', () {
    test('recognizes file-backed media without loading bytes', () {
      final request = CreateStoryRequest(
        mediaType: StoryMediaType.video,
        mediaFilePath: r'C:\tmp\story.mp4',
        mediaSizeBytes: 42,
        mediaMimeType: 'video/mp4',
      );

      expect(request.hasMedia, isTrue);
      expect(request.mediaBytes, isNull);
      expect(request.mediaSizeBytes, 42);
    });

    test('does not accept a blank file path as media', () {
      final request = CreateStoryRequest(
        mediaType: StoryMediaType.video,
        mediaFilePath: '   ',
      );

      expect(request.hasMedia, isFalse);
    });

    test('retains a stable client request id across publish retries', () {
      final request = CreateStoryRequest(
        clientRequestId: 'story_1234_retry',
        mediaType: StoryMediaType.text,
        textContent: 'A durable draft',
      );

      expect(request.clientRequestId, 'story_1234_retry');
    });

    test('clamps upload progress to a valid fraction', () {
      const belowZero = StoryCreationProgress(
        phase: StoryCreationPhase.uploadingMedia,
        uploadedBytes: -5,
        totalBytes: 10,
      );
      const complete = StoryCreationProgress(
        phase: StoryCreationPhase.uploadingMedia,
        uploadedBytes: 20,
        totalBytes: 10,
      );
      const indeterminate = StoryCreationProgress(
        phase: StoryCreationPhase.preparing,
      );

      expect(belowZero.fraction, 0);
      expect(complete.fraction, 1);
      expect(indeterminate.fraction, isNull);
    });

    test('cancellation token remains cancelled after repeated calls', () {
      final token = StoryCreationCancellationToken();

      expect(token.isCancelled, isFalse);
      token.cancel();
      token.cancel();

      expect(token.isCancelled, isTrue);
    });
  });
}

Map<String, dynamic> _validTextStory() {
  return {
    'version': Story.currentFormatVersion,
    'id': 'story-1',
    'user_id': '@owner:xmo.test',
    'user_name': 'Owner',
    'media_type': StoryMediaType.text.name,
    'text_content': 'Hello',
    'created_at': 1000,
    'expires_at': 2000,
    'viewed_by': <String>[],
    'privacy': StoryPrivacy.contacts.name,
    'custom_privacy_list': null,
  };
}
