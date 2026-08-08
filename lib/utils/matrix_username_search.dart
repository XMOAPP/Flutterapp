bool isMatrixUsernameQuery(String query) {
  final value = query.trim();
  return value.length > 1 && value.startsWith('@');
}

bool matrixUserIdMatchesUsernameQuery(String userId, String query) {
  if (!isMatrixUsernameQuery(query)) return false;

  final normalizedUserId = userId.trim().toLowerCase();
  final normalizedQuery = query.trim().toLowerCase();
  if (!normalizedUserId.startsWith('@')) return false;

  if (normalizedQuery.contains(':')) {
    return normalizedUserId.startsWith(normalizedQuery);
  }

  final separatorIndex = normalizedUserId.indexOf(':');
  final localpart = separatorIndex < 0
      ? normalizedUserId
      : normalizedUserId.substring(0, separatorIndex);
  return localpart.startsWith(normalizedQuery);
}
