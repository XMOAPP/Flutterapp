import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xmo/services/mfa_status_service.dart';

void main() {
  test('returns the authoritative enrolled status', () async {
    final service = MfaStatusService(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, endsWith('/security/mfa-status'));
        expect(request.headers['Authorization'], 'Bearer matrix-token');
        return http.Response('{"success":true,"enrolled":true}', 200);
      }),
    );

    expect(await service.isTotpEnrolled(accessToken: 'matrix-token'), isTrue);
  });

  test('accepts an authoritative not-enrolled status', () async {
    final service = MfaStatusService(
      client: MockClient(
        (_) async => http.Response('{"success":true,"enrolled":false}', 200),
      ),
    );

    expect(await service.isTotpEnrolled(accessToken: 'matrix-token'), isFalse);
  });

  test('rejects unavailable and malformed status responses', () async {
    for (final response in [
      http.Response('{"error":"unavailable"}', 502),
      http.Response('{"success":true}', 200),
    ]) {
      final service = MfaStatusService(
        client: MockClient((_) async => response),
      );
      expect(
        () => service.isTotpEnrolled(accessToken: 'matrix-token'),
        throwsA(isA<MfaStatusException>()),
      );
    }
  });
}
