import 'package:test/test.dart';

import '../lib/src/structured_logger.dart';

void main() {
  test('invite tokens are redacted from request paths', () {
    const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN123456';

    expect(
      sanitizeRequestPath('/auth/otp/invites/$token/preview'),
      '/auth/otp/invites/<redacted>/preview',
    );
    expect(
      sanitizeRequestPath('/auth/invites/$token/redeem'),
      '/auth/invites/<redacted>/redeem',
    );

    for (final prefix in const <String>[
      '/invites',
      '/auth/invites',
      '/auth/otp/invites',
    ]) {
      expect(
        sanitizeRequestPath('$prefix/$token/avatar'),
        '$prefix/<redacted>/avatar',
      );
    }
  });

  test('unrelated request paths are unchanged', () {
    expect(sanitizeRequestPath('/health'), '/health');
    expect(sanitizeRequestPath('/auth/otp/users/search'),
        '/auth/otp/users/search');
  });
}
