import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _noop(HttpRequest _) async {}

void main() {
  const module = PushGatewayEndpointModule(_noop);

  test('only exposes the standard Matrix push gateway route', () {
    expect(module.handles('/_matrix/push/v1/notify'), isTrue);
    expect(module.handles('/push'), isFalse);
    expect(module.handles('/auth/otp/push'), isFalse);
    expect(module.handles('/auth/push/_matrix/push/v1/notify'), isFalse);
    expect(module.handles('/auth/otp/_matrix/push/v1/notify'), isFalse);
  });
}
