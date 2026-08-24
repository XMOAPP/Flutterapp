import 'package:test/test.dart';
import 'package:xmo_auth_server/src/cors_policy.dart';

void main() {
  group('CorsPolicy', () {
    test('allows only the configured exact origins', () {
      final policy = CorsPolicy.fromEnvironment({});

      expect(policy.allowsOrigin('https://xmo.dpdns.org'), isTrue);
      expect(policy.allowsOrigin('https://evil.example'), isFalse);
      expect(policy.allowsOrigin('https://xmo.dpdns.org/path'), isFalse);
      expect(policy.allowsOrigin('null'), isFalse);
    });

    test('normalizes configured scheme, host, and default port', () {
      final policy = CorsPolicy.forOrigins([
        'https://XMO.DPDNS.ORG/',
        'http://localhost:8080',
      ]);

      expect(policy.allowsOrigin('https://xmo.dpdns.org:443'), isTrue);
      expect(policy.allowsOrigin('http://localhost:8080'), isTrue);
      expect(policy.allowsOrigin('http://localhost:8081'), isFalse);
    });

    test('rejects wildcard and malformed configured origins', () {
      expect(() => CorsPolicy.forOrigins(['*']), throwsArgumentError);
      expect(
        () => CorsPolicy.forOrigins(['https://xmo.dpdns.org/path']),
        throwsArgumentError,
      );
    });

    test('allows only supported preflight methods and headers', () {
      final policy = CorsPolicy.forOrigins(['https://xmo.dpdns.org']);

      expect(
        policy.allowsPreflight(
          requestMethod: 'POST',
          requestHeaders: 'content-type, authorization',
        ),
        isTrue,
      );
      expect(
        policy.allowsPreflight(
          requestMethod: 'PATCH',
          requestHeaders: 'content-type',
        ),
        isFalse,
      );
      expect(
        policy.allowsPreflight(
          requestMethod: 'POST',
          requestHeaders: 'x-api-key',
        ),
        isFalse,
      );
    });
  });
}
