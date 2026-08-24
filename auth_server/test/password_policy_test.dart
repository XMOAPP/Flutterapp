import 'package:test/test.dart';
import 'package:xmo_auth_server/src/password_policy.dart';

void main() {
  group('PasswordPolicy', () {
    test('rejects passwords shorter than fifteen characters', () {
      expect(
        PasswordPolicy.validationError('fourteenchars!'),
        'Password must be at least 15 characters',
      );
    });

    test('accepts long Unicode passphrases', () {
      expect(
        PasswordPolicy.validationError('correct horse battery staple 🔐'),
        isNull,
      );
    });

    test('accepts a 256-character password and rejects a longer one', () {
      expect(PasswordPolicy.validationError('a' * 256), isNull);
      expect(
        PasswordPolicy.validationError('a' * 257),
        'Password must be at most 256 characters',
      );
    });
  });
}
