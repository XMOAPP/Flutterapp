import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/matrix_mentions.dart';

void main() {
  group('MatrixMentions', () {
    test('builds deduplicated m.mentions content', () {
      expect(
        MatrixMentions.forUserIds([
          '@alice:example.org',
          '@alice:example.org',
          '@bob:example.org',
        ]),
        {
          'm.mentions': {
            'user_ids': ['@alice:example.org', '@bob:example.org'],
          },
        },
      );
    });

    test('removes malformed IDs and the sender own ID', () {
      expect(
        MatrixMentions.forUserIds([
          'alice',
          '@me:example.org',
          '@valid:example.org',
          '@bad:',
        ], ownUserId: '@me:example.org'),
        {
          'm.mentions': {
            'user_ids': ['@valid:example.org'],
          },
        },
      );
    });

    test('includes only autocomplete mentions still visible in text', () {
      const alice = MatrixMentionTarget(
        userId: '@alice:example.org',
        displayName: 'Alice',
      );
      const bob = MatrixMentionTarget(
        userId: '@bob:example.org',
        displayName: 'Bob Smith',
      );

      expect(MatrixMentions.forText('Hello @Alice', [alice, bob]), {
        'm.mentions': {
          'user_ids': ['@alice:example.org'],
        },
      });
    });

    test('does not match a mention inside a longer username', () {
      const target = MatrixMentionTarget(
        userId: '@ann:example.org',
        displayName: 'Ann',
      );

      expect(MatrixMentions.forText('Hello @Annabelle', [target]), isEmpty);
    });

    test('merges and deduplicates the replied-to sender', () {
      const target = MatrixMentionTarget(
        userId: '@alice:example.org',
        displayName: 'Alice',
      );

      expect(
        MatrixMentions.forText(
          '@Alice thanks',
          [target],
          additionalUserIds: const ['@alice:example.org'],
        ),
        {
          'm.mentions': {
            'user_ids': ['@alice:example.org'],
          },
        },
      );
    });
  });
}
