import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/utils/user_facing_error.dart';

void main() {
  group('userFacingError', () {
    test('does not expose network hosts or exception details', () {
      const error =
          'SocketException: Failed host lookup: internal.example.test '
          '(OS Error: No address associated with hostname)';

      final message = userFacingError(error, fallback: 'Action failed.');

      expect(
        message,
        'Connection failed. Check your internet connection and try again.',
      );
      expect(message, isNot(contains('internal.example.test')));
      expect(message, isNot(contains('SocketException')));
    });

    test('uses a safe fallback for unknown technical failures', () {
      const error = 'DatabaseException: SELECT secret FROM private_table';

      final message = userFacingError(error, fallback: 'Could not load data.');

      expect(message, 'Could not load data.');
      expect(message, isNot(contains('SELECT')));
    });

    test('preserves short plain-language service messages', () {
      final message = userFacingError(
        'Temporarily unavailable',
        fallback: 'Could not complete request.',
      );

      expect(message, 'Temporarily unavailable');
    });

    test('rejects an otherwise unknown message containing a domain', () {
      final message = userFacingError(
        'Request failed at private.internal.example',
        fallback: 'Could not complete request.',
      );

      expect(message, 'Could not complete request.');
    });

    test('keeps approved capacity guidance', () {
      final message = userFacingError(
        Exception('This channel has reached its 100-member limit.'),
        fallback: 'Could not join channel.',
      );

      expect(message, 'This channel has reached its 100-member limit.');
    });

    test('legacy UI text retains only its safe action', () {
      const message =
          'Failed to send message: DatabaseException: private query details';

      final safe = safeUserFacingText(message);

      expect(safe, 'Failed to send message.');
      expect(safe, isNot(contains('DatabaseException')));
      expect(safe, isNot(contains('private query')));
    });

    test('does not expose the production homeserver hostname', () {
      const error =
          'ClientException: request failed, uri=https://'
          'xmo-matrix.centralindia.cloudapp.azure.com/_matrix/client/v3/sync';

      final message = userFacingError(error, fallback: 'Sync failed.');

      expect(
        message,
        'Connection failed. Check your internet connection and try again.',
      );
      expect(
        message,
        isNot(contains('xmo-matrix.centralindia.cloudapp.azure.com')),
      );
    });

    test('sanitizes persisted legacy upload failures', () {
      const message =
          'SocketException: Failed host lookup: '
          'xmo-matrix.centralindia.cloudapp.azure.com';

      final safe = safeUserFacingText(message, fallback: 'Upload failed.');

      expect(
        safe,
        'Connection failed. Check your internet connection and try again.',
      );
    });
  });
}
