class MatrixMentionTarget {
  final String userId;
  final String displayName;

  const MatrixMentionTarget({required this.userId, required this.displayName});
}

class MatrixMentions {
  static const String contentKey = 'm.mentions';

  static Map<String, dynamic> forUserIds(
    Iterable<String> userIds, {
    String? ownUserId,
  }) {
    final normalizedOwnUserId = ownUserId?.trim();
    final uniqueUserIds = <String>{};

    for (final userId in userIds) {
      final normalized = userId.trim();
      if (!_isValidUserId(normalized) || normalized == normalizedOwnUserId) {
        continue;
      }
      uniqueUserIds.add(normalized);
    }

    if (uniqueUserIds.isEmpty) return const {};
    return {
      contentKey: {'user_ids': uniqueUserIds.toList(growable: false)},
    };
  }

  static Map<String, dynamic> forText(
    String text,
    Iterable<MatrixMentionTarget> selectedTargets, {
    Iterable<String> additionalUserIds = const [],
    String? ownUserId,
  }) {
    final visibleUserIds = selectedTargets
        .where((target) => _containsVisibleMention(text, target.displayName))
        .map((target) => target.userId);

    return forUserIds([
      ...visibleUserIds,
      ...additionalUserIds,
    ], ownUserId: ownUserId);
  }

  static bool _containsVisibleMention(String text, String displayName) {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) return false;

    final token = '@$normalizedName';
    var index = text.indexOf(token);
    while (index >= 0) {
      final beforeIsValid =
          index == 0 ||
          !_isMentionContinuation(text.substring(index - 1, index));
      final end = index + token.length;
      final afterIsValid =
          end == text.length ||
          !_isMentionContinuation(text.substring(end, end + 1));
      if (beforeIsValid && afterIsValid) return true;
      index = text.indexOf(token, index + token.length);
    }
    return false;
  }

  static bool _isMentionContinuation(String character) {
    return RegExp(r'[\p{L}\p{N}_@]', unicode: true).hasMatch(character);
  }

  static bool _isValidUserId(String userId) {
    if (!userId.startsWith('@') || RegExp(r'\s').hasMatch(userId)) {
      return false;
    }
    final separator = userId.indexOf(':');
    return separator > 1 && separator < userId.length - 1;
  }
}
