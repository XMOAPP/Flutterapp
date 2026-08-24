/// Shared client-side password rules.
///
/// The auth server enforces the same policy. This copy provides immediate UI
/// feedback only and must never be relied on as the security boundary.
class PasswordPolicy {
  static const minimumLength = 15;
  static const maximumLength = 256;

  static String? validationError(String password) {
    final length = password.runes.length;
    if (length < minimumLength) {
      return 'Password must be at least $minimumLength characters';
    }
    if (length > maximumLength) {
      return 'Password must be at most $maximumLength characters';
    }
    return null;
  }
}
