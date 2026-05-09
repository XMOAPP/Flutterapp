import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/matrix_service.dart';

void main() {
  group('MatrixService invite links', () {
    test('buildMatrixToLink encodes room identifiers', () {
      expect(
        MatrixService.buildMatrixToLink('!abc:localhost'),
        'https://matrix.to/#/!abc%3Alocalhost',
      );
    });

    test('extractRoomIdentifier accepts raw room ids and aliases', () {
      expect(
        MatrixService.extractRoomIdentifier('!abc:localhost'),
        '!abc:localhost',
      );
      expect(
        MatrixService.extractRoomIdentifier('#general:localhost'),
        '#general:localhost',
      );
    });

    test('extractRoomIdentifier accepts matrix.to room links', () {
      expect(
        MatrixService.extractRoomIdentifier(
          'https://matrix.to/#/%21abc%3Alocalhost',
        ),
        '!abc:localhost',
      );
      expect(
        MatrixService.extractRoomIdentifier(
          'https://matrix.to/#/%23general%3Alocalhost',
        ),
        '#general:localhost',
      );
    });

    test('extractRoomIdentifier ignores encoded XMO invite tokens', () {
      expect(
        MatrixService.extractRoomIdentifier(
          'https://matrix.to/#/!abc%3Alocalhost?xmo_invite=123',
        ),
        '!abc:localhost',
      );
      expect(
        MatrixService.extractRoomIdentifier(
          MatrixService.buildMatrixToLink('!abc:localhost?xmo_invite=123'),
        ),
        '!abc:localhost',
      );
    });

    test('extractRoomIdentifier rejects unrelated strings', () {
      expect(MatrixService.extractRoomIdentifier('general'), isNull);
      expect(
          MatrixService.extractRoomIdentifier('https://example.com'), isNull);
    });
  });
}
