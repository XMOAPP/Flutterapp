import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/mfa_setup_completion_service.dart';

void main() {
  test('accepts only the dedicated verified completion callback', () {
    expect(
      MfaSetupCompletionService.isCompletionUri(
        Uri.parse(
          'https://xmo.dpdns.org/auth/callback?'
          'xmo_action=mfa_setup_complete',
        ),
      ),
      isTrue,
    );
    expect(
      MfaSetupCompletionService.isCompletionUri(
        Uri.parse(
          'https://evil.example/auth/callback?'
          'xmo_action=mfa_setup_complete',
        ),
      ),
      isFalse,
    );
    expect(
      MfaSetupCompletionService.isCompletionUri(
        Uri.parse(
          'https://xmo.dpdns.org/auth/callback?'
          'xmo_action=mfa_setup_complete&xmo_action=mfa_setup_complete',
        ),
      ),
      isFalse,
    );
    expect(
      MfaSetupCompletionService.isCompletionUri(
        Uri.parse(
          'https://xmo.dpdns.org/auth/callback?state=abc&loginToken=token',
        ),
      ),
      isFalse,
    );
    expect(
      MfaSetupCompletionService.isCompletionUri(
        Uri.parse(
          'https://xmo.dpdns.org/auth/callback?'
          'xmo_action=mfa_setup_complete&loginToken=token',
        ),
      ),
      isFalse,
    );
  });
}
