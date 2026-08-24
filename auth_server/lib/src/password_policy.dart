/// Password rules enforced at every XMO server password-creation boundary.
///
/// The client mirrors these limits for immediate feedback, but this policy is
/// authoritative because API clients can bypass the Flutter UI.
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
