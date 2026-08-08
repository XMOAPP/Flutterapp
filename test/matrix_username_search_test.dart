import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/utils/matrix_username_search.dart';

void main() {
  group('Matrix username account search', () {
    test('requires an at-prefixed query', () {
      expect(isMatrixUsernameQuery('alice'), isFalse);
      expect(isMatrixUsernameQuery('@'), isFalse);
      expect(isMatrixUsernameQuery('@alice'), isTrue);
    });

    test('matches username localparts without using display names', () {
      expect(
        matrixUserIdMatchesUsernameQuery('@alice:xmo.org', '@ali'),
        isTrue,
      );
      expect(
        matrixUserIdMatchesUsernameQuery('@bob:xmo.org', '@alice'),
        isFalse,
      );
      expect(
        matrixUserIdMatchesUsernameQuery('@alice:xmo.org', 'Alice Smith'),
        isFalse,
      );
    });

    test('supports full Matrix IDs and ignores case', () {
      expect(
        matrixUserIdMatchesUsernameQuery('@Alice:XMO.org', '@alice:xmo.org'),
        isTrue,
      );
      expect(
        matrixUserIdMatchesUsernameQuery('@alice:other.org', '@alice:xmo.org'),
        isFalse,
      );
    });
  });
}
