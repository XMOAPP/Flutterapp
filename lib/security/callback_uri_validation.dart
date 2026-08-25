/// Validation helpers for security-sensitive app callbacks.
///
/// Deep links can be invoked by other applications, so callback consumers must
/// reject ambiguous query strings before reading a value from them.
bool hasOnlySingleAllowedQueryParameters(Uri uri, Set<String> allowedKeys) {
  if (uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) return false;
  for (final entry in uri.queryParametersAll.entries) {
    if (!allowedKeys.contains(entry.key) || entry.value.length != 1) {
      return false;
    }
  }
  return true;
}
