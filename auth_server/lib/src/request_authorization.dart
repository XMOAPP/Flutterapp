part of xmo_auth_server;

/// Request-scoped Matrix identity resolved by the authorization boundary.
///
/// Keeping this outside request headers/body prevents callers from supplying a
/// user identity and avoids repeated Synapse `whoami` calls in one request.
class _MatrixRequestPrincipal {
  const _MatrixRequestPrincipal({required this.token, required this.userId});

  final String token;
  final String userId;
}

final _matrixRequestPrincipals = Expando<_MatrixRequestPrincipal>(
  'matrixRequestPrincipal',
);
final _pushTrustedPeers = TrustedProxyConfig.fromCidrs(
  (Platform.environment['XMO_PUSH_TRUSTED_CIDRS'] ?? '').split(','),
);

Future<bool> _authorizeEndpoint(
  HttpRequest request,
  EndpointAuthorizationPolicy policy,
) async {
  switch (policy) {
    case EndpointAuthorizationPolicy.public:
    case EndpointAuthorizationPolicy.proofBased:
    case EndpointAuthorizationPolicy.capability:
      return true;
    case EndpointAuthorizationPolicy.matrixUser:
      return _authorizeMatrixUser(request);
    case EndpointAuthorizationPolicy.internalService:
      return _authorizeInternalService(request);
  }
}

Future<bool> _authorizeMatrixUser(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _unauthorized(request);
    return false;
  }

  try {
    final userId = await _userDirectoryWhoami(token);
    _matrixRequestPrincipals[request] = _MatrixRequestPrincipal(
      token: token,
      userId: userId,
    );
    return true;
  } catch (_) {
    await _unauthorized(request);
    return false;
  }
}

Future<bool> _authorizeInternalService(HttpRequest request) async {
  final peerAddress = request.connectionInfo?.remoteAddress.address ?? '';
  if (_pushTrustedPeers.isTrusted(peerAddress)) return true;

  logWarning('internal_service_request_rejected', {
    'path': sanitizeRequestPath(request.uri.path),
  });
  await _json(request, HttpStatus.forbidden, {
    'error': 'Service access required',
  });
  return false;
}

Future<void> _unauthorized(HttpRequest request) => _json(
  request,
  HttpStatus.unauthorized,
  {'error': 'Valid XMO session required'},
);

/// Returns the identity resolved by the centralized middleware when possible.
/// The fallback keeps helper-level behavior safe for internal calls and tests.
Future<String> _userDirectoryWhoamiForRequest(
  HttpRequest request,
  String token,
) async {
  final principal = _matrixRequestPrincipals[request];
  if (principal != null && principal.token == token) return principal.userId;
  return _userDirectoryWhoami(token);
}
