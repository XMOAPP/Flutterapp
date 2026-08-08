class MatrixIdentity {
  const MatrixIdentity._();

  static final RegExp _fullUserIdPattern = RegExp(r'^@[^:\s]+:[^\s]+$');

  static bool isFullUserId(String? value) {
    final candidate = value?.trim();
    return candidate != null && _fullUserIdPattern.hasMatch(candidate);
  }

  static String localpart(String userId) {
    var value = userId.trim();
    if (value.startsWith('@')) value = value.substring(1);
    final separator = value.indexOf(':');
    if (separator >= 0) value = value.substring(0, separator);
    return value.trim();
  }

  static String usernameLabel(String userId) {
    final username = localpart(userId);
    return username.isEmpty ? '' : '@$username';
  }

  static bool isFriendlyDisplayName(String? value, String userId) {
    final candidate = value?.trim();
    if (candidate == null || candidate.isEmpty) return false;
    if (candidate == userId.trim() || isFullUserId(candidate)) return false;
    return true;
  }

  static String displayName({
    required String userId,
    String? candidate,
    String fallback = 'Unknown',
  }) {
    if (isFriendlyDisplayName(candidate, userId)) return candidate!.trim();
    final username = localpart(userId);
    if (username.isEmpty) return fallback;
    return '${username[0].toUpperCase()}${username.substring(1)}';
  }
}
