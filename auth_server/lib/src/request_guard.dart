import 'dart:io';

class RequestRateLimiter {
  RequestRateLimiter({
    this.window = const Duration(minutes: 1),
    this.maxRequestsPerWindow = 60,
    TrustedProxyConfig? trustedProxies,
  }) : trustedProxies = trustedProxies ?? TrustedProxyConfig.empty();

  final Duration window;
  final int maxRequestsPerWindow;
  final TrustedProxyConfig trustedProxies;
  final Map<String, _RateWindow> _windows = <String, _RateWindow>{};

  bool allow(HttpRequest request, {String? routeKey}) {
    final key = '${_clientAddress(request)}:${routeKey ?? request.uri.path}';
    final now = DateTime.now().toUtc();
    final current = _windows[key];
    if (current == null || now.difference(current.startedAt) >= window) {
      _windows[key] = _RateWindow(now, 1);
      _removeExpired(now);
      return true;
    }
    if (current.count >= maxRequestsPerWindow) return false;
    current.count += 1;
    return true;
  }

  String _clientAddress(HttpRequest request) {
    return resolveRequestClientAddress(request, trustedProxies: trustedProxies);
  }

  void _removeExpired(DateTime now) {
    _windows.removeWhere(
      (_, value) => now.difference(value.startedAt) > window * 2,
    );
  }
}

String resolveRequestClientAddress(
  HttpRequest request, {
  required TrustedProxyConfig trustedProxies,
}) => resolveClientAddress(
  peerAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
  forwardedFor: request.headers.value('x-real-ip'),
  trustedProxies: trustedProxies,
);

/// A narrow allow-list of reverse proxies allowed to supply a client address.
///
/// Requests from every other peer are identified by their direct TCP address,
/// even when they contain an `X-Real-IP` header.
class TrustedProxyConfig {
  TrustedProxyConfig.empty() : _networks = const <_IpNetwork>[];

  TrustedProxyConfig.fromCidrs(Iterable<String> cidrs)
    : _networks = cidrs
          .map((cidr) => cidr.trim())
          .where((cidr) => cidr.isNotEmpty)
          .map(_IpNetwork.parse)
          .toList(growable: false);

  factory TrustedProxyConfig.fromEnvironment(Map<String, String> environment) {
    final configured = environment['XMO_TRUSTED_PROXY_CIDRS'] ?? '';
    return TrustedProxyConfig.fromCidrs(configured.split(','));
  }

  final List<_IpNetwork> _networks;

  bool isTrusted(String address) {
    final parsed = _parseIpAddress(address);
    return parsed != null &&
        _networks.any((network) => network.contains(parsed));
  }
}

/// Resolves the rate-limit identity for a request without trusting an
/// application-controlled forwarding header.
String resolveClientAddress({
  required String peerAddress,
  required String? forwardedFor,
  required TrustedProxyConfig trustedProxies,
}) {
  final directPeer = _parseIpAddress(peerAddress);
  final directAddress = directPeer?.address ?? 'unknown';
  if (directPeer == null || !trustedProxies.isTrusted(directAddress)) {
    return directAddress;
  }

  // Caddy is configured to replace this header with one canonical client IP.
  // Treat a chain or malformed value as untrusted rather than guessing which
  // hop is safe to use.
  final forwarded = forwardedFor?.trim() ?? '';
  if (forwarded.isEmpty || forwarded.contains(',')) return directAddress;
  return _parseIpAddress(forwarded)?.address ?? directAddress;
}

InternetAddress? _parseIpAddress(String value) {
  try {
    return InternetAddress(value.trim());
  } on Object {
    return null;
  }
}

class _IpNetwork {
  const _IpNetwork(this.network, this.prefixLength);

  factory _IpNetwork.parse(String cidr) {
    final slash = cidr.lastIndexOf('/');
    final addressText = slash == -1 ? cidr : cidr.substring(0, slash);
    final address = _parseIpAddress(addressText);
    if (address == null) {
      throw ArgumentError.value(cidr, 'cidr', 'Invalid trusted proxy address');
    }

    final maxPrefix = address.rawAddress.length * 8;
    final prefixLength = slash == -1
        ? maxPrefix
        : int.tryParse(cidr.substring(slash + 1));
    if (prefixLength == null || prefixLength < 0 || prefixLength > maxPrefix) {
      throw ArgumentError.value(cidr, 'cidr', 'Invalid trusted proxy CIDR');
    }
    return _IpNetwork(address, prefixLength);
  }

  final InternetAddress network;
  final int prefixLength;

  bool contains(InternetAddress candidate) {
    final expected = network.rawAddress;
    final actual = candidate.rawAddress;
    if (expected.length != actual.length) return false;

    final completeBytes = prefixLength ~/ 8;
    for (var index = 0; index < completeBytes; index += 1) {
      if (expected[index] != actual[index]) return false;
    }
    final remainingBits = prefixLength % 8;
    if (remainingBits == 0) return true;
    final mask = (0xff << (8 - remainingBits)) & 0xff;
    return (expected[completeBytes] & mask) == (actual[completeBytes] & mask);
  }
}

class _RateWindow {
  _RateWindow(this.startedAt, this.count);
  final DateTime startedAt;
  int count;
}
