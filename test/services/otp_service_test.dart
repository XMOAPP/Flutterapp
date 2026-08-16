import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xmo/services/otp_service.dart';

void main() {
  group('OtpService secure sign-in enrollment', () {
    test('checks username availability before registration OTP', () async {
      final service = OtpService.forTesting(
        otpServerUrl: 'https://example.test/auth/otp',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/otp/accounts/username-availability');
          expect(jsonDecode(request.body), {'username': 'alice'});
          return http.Response(
            jsonEncode({'success': true, 'available': false}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await service.checkUsernameAvailability('alice');

      expect(result.success, isTrue);
      expect(result.available, isFalse);
      expect(result.error, isNull);
    });

    test(
      'does not treat an availability service failure as username taken',
      () async {
        final service = OtpService.forTesting(
          otpServerUrl: 'https://example.test/auth/otp',
          client: MockClient((_) async {
            return http.Response(
              jsonEncode({'error': 'Temporarily unavailable'}),
              503,
            );
          }),
        );

        final result = await service.checkUsernameAvailability('alice');

        expect(result.success, isFalse);
        expect(result.available, isNull);
        expect(result.error, 'Temporarily unavailable');
      },
    );

    test('keeps the enrollment proof returned by OTP verification', () async {
      final service = OtpService.forTesting(
        otpServerUrl: 'https://example.test/auth/otp',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/otp/verify');
          expect(jsonDecode(request.body), {
            'email': 'person@example.com',
            'otp': '123456',
          });
          return http.Response(
            jsonEncode({
              'success': true,
              'secureLoginEnrollmentProof': ' enrollment-proof ',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await service.verifyOtp(
        email: 'person@example.com',
        code: '123456',
      );

      expect(result.verified, isTrue);
      expect(result.secureLoginEnrollmentProof, 'enrollment-proof');
    });

    test('provisions secure sign-in after Matrix registration', () async {
      final service = OtpService.forTesting(
        otpServerUrl: 'https://example.test/auth/otp',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/otp/users/provision-secure-login');
          expect(request.headers['authorization'], 'Bearer matrix-token');
          expect(jsonDecode(request.body), {
            'username': 'alice',
            'email': 'person@example.com',
            'password': 'secret-password',
            'secureLoginEnrollmentProof': 'enrollment-proof',
          });
          return http.Response(
            jsonEncode({'success': true, 'configured': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await service.provisionSecureLogin(
        username: 'alice',
        email: 'person@example.com',
        password: 'secret-password',
        accessToken: 'matrix-token',
        secureLoginEnrollmentProof: 'enrollment-proof',
      );

      expect(result.success, isTrue);
    });

    test('registers an OIDC-only account after email verification', () async {
      final service = OtpService.forTesting(
        otpServerUrl: 'https://example.test/auth/otp',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/otp/accounts/register');
          expect(jsonDecode(request.body), {
            'username': 'alice',
            'email': 'person@example.com',
            'password': 'secret-password',
            'secureLoginEnrollmentProof': 'enrollment-proof',
          });
          return http.Response(
            jsonEncode({
              'success': true,
              'username': 'alice',
              'userId': '@alice:example.test',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await service.registerOidcAccount(
        username: 'alice',
        email: 'person@example.com',
        password: 'secret-password',
        secureLoginEnrollmentProof: 'enrollment-proof',
      );

      expect(result.success, isTrue);
      expect(result.error, isNull);
    });

    test('does not register an OIDC account without an OTP proof', () async {
      final service = OtpService.forTesting(
        otpServerUrl: 'https://example.test/auth/otp',
        client: MockClient((request) async {
          fail('The server must not be called without an enrollment proof.');
        }),
      );

      final result = await service.registerOidcAccount(
        username: 'alice',
        email: 'person@example.com',
        password: 'secret-password',
        secureLoginEnrollmentProof: '',
      );

      expect(result.success, isFalse);
      expect(result.error, contains('verification expired'));
    });

    test('does not call provisioning without its Matrix token', () async {
      final service = OtpService.forTesting(
        otpServerUrl: 'https://example.test/auth/otp',
        client: MockClient((request) async {
          fail('The server must not be called without a Matrix token.');
        }),
      );

      final result = await service.provisionSecureLogin(
        username: 'alice',
        email: 'person@example.com',
        password: 'secret-password',
        accessToken: '',
        secureLoginEnrollmentProof: 'enrollment-proof',
      );

      expect(result.success, isFalse);
      expect(result.error, contains('verification is missing'));
    });
  });
}
