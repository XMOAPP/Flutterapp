import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/matrix_media_helper.dart';

void main() {
  group('MatrixMediaHelper', () {
    const helper = MatrixMediaHelper(
      homeserverUrl: 'https://matrix.example.org',
      accessToken: 'secret-token',
    );

    test('builds authenticated download requests without token query params',
        () {
      final request = helper.fromMxc('mxc://example.org/media-id');

      expect(request, isNotNull);
      expect(
        request!.uri.toString(),
        'https://matrix.example.org/_matrix/client/v1/media/download/example.org/media-id',
      );
      expect(request.uri.queryParameters.containsKey('access_token'), isFalse);
      expect(request.headers, {'Authorization': 'Bearer secret-token'});
    });

    test('builds authenticated thumbnail requests with only media options', () {
      final request = helper.fromMxc(
        'mxc://example.org/media-id',
        width: 96,
        height: 96,
      );

      expect(request, isNotNull);
      expect(
        request!.uri.path,
        '/_matrix/client/v1/media/thumbnail/example.org/media-id',
      );
      expect(request.uri.queryParameters, {
        'width': '96',
        'height': '96',
        'method': 'scale',
      });
      expect(request.headers, {'Authorization': 'Bearer secret-token'});
    });

    test('normalizes legacy SDK media URLs and strips access tokens', () {
      final request = helper.fromUrl(
        Uri.parse(
          'https://matrix.example.org/_matrix/media/v3/download/example.org/media-id'
          '?access_token=leaked&allow_redirect=true',
        ),
      );

      expect(
        request.uri.toString(),
        'https://matrix.example.org/_matrix/client/v1/media/download/example.org/media-id'
        '?allow_redirect=true',
      );
      expect(request.uri.queryParameters.containsKey('access_token'), isFalse);
      expect(request.headers, {'Authorization': 'Bearer secret-token'});
    });

    test('does not attach Matrix credentials to non-Matrix URLs', () {
      final request = helper.fromUrl(
        Uri.parse('https://cdn.example.org/avatar.jpg?access_token=legacy'),
      );

      expect(request.uri.toString(), 'https://cdn.example.org/avatar.jpg');
      expect(request.headers, isEmpty);
    });
  });
}
