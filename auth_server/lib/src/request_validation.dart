String requireStringField(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid "$key"');
  }
  return value.trim();
}

int requirePositiveIntField(Map<String, Object?> body, String key) {
  final value = body[key];
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed <= 0) {
    throw FormatException('Missing or invalid "$key"');
  }
  return parsed;
}
