import 'dart:io';

/// Exact browser origins permitted to read XMO auth-server responses.
///
/// This is intentionally an allow-list: arbitrary request origins are never
/// reflected. Requests without an Origin header are non-browser/internal
/// traffic and are not subject to CORS.
class CorsPolicy {
  CorsPolicy.fromEnvironment(Map<String, String> environment)
    : _allowedOrigins = _parseOrigins(
        environment['XMO_ALLOWED_CORS_ORIGINS'] ?? 'https://xmo.dpdns.org',
      );

  CorsPolicy.forOrigins(Iterable<String> origins)
    : _allowedOrigins = _parseOrigins(origins.join(','));

  final Set<String> _allowedOrigins;

  static const allowedMethods = {'GET', 'POST'};
  static const allowedHeaders = {'content-type', 'authorization'};

  bool allowsOrigin(String origin) {
    final normalized = _normalizeRequestOrigin(origin);
    return normalized != null && _allowedOrigins.contains(normalized);
  }

  bool allowsPreflight({
    required String? requestMethod,
    required String? requestHeaders,
  }) {
    if (requestMethod == null ||
        !allowedMethods.contains(requestMethod.trim().toUpperCase())) {
      return false;
    }
    if (requestHeaders == null || requestHeaders.trim().isEmpty) return true;
    return requestHeaders
        .split(',')
        .map((header) => header.trim().toLowerCase())
        .every(allowedHeaders.contains);
  }

  void applyHeaders(HttpResponse response, String origin) {
    response.headers.set('Access-Control-Allow-Origin', origin);
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization',
    );
    response.headers.set('Vary', 'Origin');
  }

  static Set<String> _parseOrigins(String rawOrigins) {
    final values = rawOrigins
        .split(',')
        .map((origin) => origin.trim())
        .where((origin) => origin.isNotEmpty)
        .map(_normalizeConfiguredOrigin)
        .toSet();
    if (values.isEmpty) {
      throw ArgumentError.value(
        rawOrigins,
        'XMO_ALLOWED_CORS_ORIGINS',
        'At least one allowed CORS origin is required',
      );
    }
    return values;
  }

  static String _normalizeConfiguredOrigin(String origin) {
    final normalized = _normalizeOrigin(origin, allowTrailingSlash: true);
    if (normalized == null) {
      throw ArgumentError.value(
        origin,
        'origin',
        'Invalid allowed CORS origin',
      );
    }
    return normalized;
  }

  static String? _normalizeRequestOrigin(String origin) =>
      _normalizeOrigin(origin, allowTrailingSlash: false);

  static String? _normalizeOrigin(
    String origin, {
    required bool allowTrailingSlash,
  }) {
    final value = origin.trim();
    if (value.isEmpty || value == 'null' || value == '*') return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (!allowTrailingSlash && uri.path.isNotEmpty) ||
        (allowTrailingSlash && uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return null;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;
    final isDefaultPort =
        uri.port == 0 ||
        (scheme == 'https' && uri.port == 443) ||
        (scheme == 'http' && uri.port == 80);
    return '$scheme://$host${isDefaultPort ? '' : ':${uri.port}'}';
  }
}
