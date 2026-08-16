import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/account_deletion_completion_service.dart';

void main() {
  group('AccountDeletionCompletionService', () {
    test('accepts the verified HTTPS deletion callback', () {
      expect(
        AccountDeletionCompletionService.isCompletionUri(
          Uri.parse(
            'https://xmo.dpdns.org/auth/callback?'
            'xmo_action=account_deleted&user_id=%40alice%3Aexample.org',
          ),
        ),
        isFalse,
      );
      expect(
        AccountDeletionCompletionService.isCompletionUri(
          Uri.parse(
            'https://xmo.dpdns.org/account/deleted?'
            'xmo_action=account_deleted&user_id=%40alice%3Aexample.org',
          ),
        ),
        isTrue,
      );
    });

    test('accepts only the dedicated custom-scheme fallback', () {
      expect(
        AccountDeletionCompletionService.isCompletionUri(
          Uri.parse(
            'xmo://account/deleted?'
            'xmo_action=account_deleted&user_id=%40alice%3Aexample.org',
          ),
        ),
        isTrue,
      );
      expect(
        AccountDeletionCompletionService.isCompletionUri(
          Uri.parse(
            'xmo://auth/callback?'
            'xmo_action=account_deleted&user_id=%40alice%3Aexample.org',
          ),
        ),
        isFalse,
      );
    });

    test('rejects incomplete, forged, or overbroad callbacks', () {
      expect(
        AccountDeletionCompletionService.isCompletionUri(
          Uri.parse(
            'https://evil.example/auth/callback?xmo_action=account_deleted&user_id=%40alice%3Aexample.org',
          ),
        ),
        isFalse,
      );
      expect(
        AccountDeletionCompletionService.isCompletionUri(
          Uri.parse('xmo://account/deleted?xmo_action=account_deleted'),
        ),
        isFalse,
      );
      expect(
        AccountDeletionCompletionService.isCompletionUri(
          Uri.parse(
            'xmo://account/deleted?xmo_action=account_deleted&user_id=%40alice%3Aexample.org&next=bad',
          ),
        ),
        isFalse,
      );
    });
  });
}
