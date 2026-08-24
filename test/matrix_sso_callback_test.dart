import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/matrix_sso_service.dart';

void main() {
  test(
    'accepts only the configured verified HTTPS callback origin and path',
    () {
      expect(
        MatrixSsoService.isSupportedCallbackUri(
          Uri.parse(
            'https://xmo.dpdns.org/auth/callback?state=abc&loginToken=token',
          ),
        ),
        isTrue,
      );
      expect(
        MatrixSsoService.isSupportedCallbackUri(
          Uri.parse('https://evil.example/auth/callback?loginToken=token'),
        ),
        isFalse,
      );
      expect(
        MatrixSsoService.isSupportedCallbackUri(
          Uri.parse('https://xmo.dpdns.org/auth/callback?state=one&state=two'),
        ),
        isFalse,
      );
      expect(
        MatrixSsoService.isSupportedCallbackUri(
          Uri.parse('xmo://auth/callback?loginToken=token'),
        ),
        isFalse,
      );
    },
  );
}
