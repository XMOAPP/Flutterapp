import 'package:test/test.dart';
import 'package:xmo_auth_server/src/request_guard.dart';

void main() {
  final caddyOnly = TrustedProxyConfig.fromCidrs(['172.18.0.4/32']);

  group('resolveClientAddress', () {
    test('ignores a forwarded address from an untrusted peer', () {
      expect(
        resolveClientAddress(
          peerAddress: '172.18.0.9',
          forwardedFor: '203.0.113.50',
          trustedProxies: caddyOnly,
        ),
        '172.18.0.9',
      );
    });

    test('uses a valid forwarded address from the trusted Caddy peer', () {
      expect(
        resolveClientAddress(
          peerAddress: '172.18.0.4',
          forwardedFor: '203.0.113.50',
          trustedProxies: caddyOnly,
        ),
        '203.0.113.50',
      );
    });

    test('fails closed for malformed or multi-hop forwarded values', () {
      for (final header in <String>[
        '',
        'not-an-ip',
        '203.0.113.50, 198.51.100.10',
      ]) {
        expect(
          resolveClientAddress(
            peerAddress: '172.18.0.4',
            forwardedFor: header,
            trustedProxies: caddyOnly,
          ),
          '172.18.0.4',
          reason: 'header: $header',
        );
      }
    });

    test('supports a narrowly configured IPv6 trusted proxy', () {
      final config = TrustedProxyConfig.fromCidrs(['fd00::4/128']);
      expect(
        resolveClientAddress(
          peerAddress: 'fd00::4',
          forwardedFor: '2001:db8::50',
          trustedProxies: config,
        ),
        '2001:db8::50',
      );
    });

    test('rejects invalid trusted proxy configuration', () {
      expect(
        () => TrustedProxyConfig.fromCidrs(['172.18.0.4/99']),
        throwsArgumentError,
      );
    });
  });
}
