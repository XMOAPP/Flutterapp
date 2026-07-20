import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _handler(HttpRequest _) async {}

void main() {
  const module = ReportEndpointModule(
    submit: _handler,
    list: _handler,
    update: _handler,
  );

  test('report route aliases are recognized', () {
    expect(module.handlesSubmit('/auth/otp/reports/submit'), isTrue);
    expect(module.handlesList('/auth/otp/reports/review/list'), isTrue);
    expect(module.handlesUpdate('/auth/otp/reports/review/update'), isTrue);
    expect(module.handlesSubmit('/reports/review/list'), isFalse);
  });
}
