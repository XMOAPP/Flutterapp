import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/security/password_policy.dart';

void main() {
  test('client mirrors the server password length limits', () {
    expect(
      PasswordPolicy.validationError('fourteenchars!'),
      'Password must be at least 15 characters',
    );
    expect(
      PasswordPolicy.validationError('correct horse battery staple 🔐'),
      isNull,
    );
    expect(
      PasswordPolicy.validationError('a' * 257),
      'Password must be at most 256 characters',
    );
  });
}
