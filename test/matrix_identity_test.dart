import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/utils/matrix_identity.dart';

void main() {
  group('MatrixIdentity', () {
    const userId = '@hunter:xmo.example.com';

    test('extracts localpart and username label', () {
      expect(MatrixIdentity.localpart(userId), 'hunter');
      expect(MatrixIdentity.usernameLabel(userId), '@hunter');
    });

    test('preserves a valid display name', () {
      expect(
        MatrixIdentity.displayName(userId: userId, candidate: 'Hunter Three'),
        'Hunter Three',
      );
    });

    test('falls back for missing or full Matrix ID display names', () {
      expect(MatrixIdentity.displayName(userId: userId), 'Hunter');
      expect(
        MatrixIdentity.displayName(userId: userId, candidate: userId),
        'Hunter',
      );
      expect(
        MatrixIdentity.displayName(
          userId: userId,
          candidate: '@someone:else.example.com',
        ),
        'Hunter',
      );
    });

    test('does not corrupt ordinary names containing a colon', () {
      expect(
        MatrixIdentity.displayName(userId: userId, candidate: 'Support: India'),
        'Support: India',
      );
    });

    test('uses explicit fallback for an unusable ID', () {
      expect(
        MatrixIdentity.displayName(userId: '  ', fallback: 'Unknown user'),
        'Unknown user',
      );
      expect(MatrixIdentity.usernameLabel('  '), isEmpty);
    });
  });
}
