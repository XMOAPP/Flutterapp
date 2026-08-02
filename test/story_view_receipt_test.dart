import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/story_models.dart';

void main() {
  group('story view receipt validation', () {
    final serverTime = DateTime.fromMillisecondsSinceEpoch(123456);

    test('accepts a receipt whose claimed viewer matches the sender', () {
      final receipt = parseStoryViewReceipt(
        content: const {
          'story_id': 'story-1',
          'viewer_id': '@viewer:xmo.test',
          'viewed_at': 1,
        },
        senderId: '@viewer:xmo.test',
        receivedAt: serverTime,
      );

      expect(receipt?.storyId, 'story-1');
      expect(receipt?.viewerId, '@viewer:xmo.test');
      expect(receipt?.viewedAt, serverTime);
    });

    test('supports legacy receipts without a claimed viewer', () {
      final receipt = parseStoryViewReceipt(
        content: const {'story_id': 'story-1'},
        senderId: '@viewer:xmo.test',
        receivedAt: serverTime,
      );

      expect(receipt?.viewerId, '@viewer:xmo.test');
    });

    test('rejects a forged viewer id', () {
      final receipt = parseStoryViewReceipt(
        content: const {
          'story_id': 'story-1',
          'viewer_id': '@victim:xmo.test',
        },
        senderId: '@attacker:xmo.test',
        receivedAt: serverTime,
      );

      expect(receipt, isNull);
    });

    test('rejects receipts without a story id or sender', () {
      expect(
        parseStoryViewReceipt(
          content: const {},
          senderId: '@viewer:xmo.test',
          receivedAt: serverTime,
        ),
        isNull,
      );
      expect(
        parseStoryViewReceipt(
          content: const {'story_id': 'story-1'},
          senderId: '',
          receivedAt: serverTime,
        ),
        isNull,
      );
    });

    test('uses the server timestamp instead of client supplied time', () {
      final receipt = parseStoryViewReceipt(
        content: const {
          'story_id': 'story-1',
          'viewed_at': 999999999,
        },
        senderId: '@viewer:xmo.test',
        receivedAt: serverTime,
      );

      expect(receipt?.viewedAt, serverTime);
    });

    test('rejects malformed and oversized identifiers', () {
      expect(
        parseStoryViewReceipt(
          content: const {'story_id': 42},
          senderId: '@viewer:xmo.test',
          receivedAt: serverTime,
        ),
        isNull,
      );
      expect(
        parseStoryViewReceipt(
          content: const {
            'story_id': 'story-1',
            'viewer_id': 42,
          },
          senderId: '@viewer:xmo.test',
          receivedAt: serverTime,
        ),
        isNull,
      );
      expect(
        parseStoryViewReceipt(
          content: {'story_id': 's' * (Story.maxIdLength + 1)},
          senderId: '@viewer:xmo.test',
          receivedAt: serverTime,
        ),
        isNull,
      );
    });
  });
}
