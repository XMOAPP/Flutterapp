import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _noop(HttpRequest _) async {}

void main() {
  const module = ChannelAnalyticsEndpointModule(
    view: _noop,
    forward: _noop,
    stats: _noop,
  );

  test('matches channel analytics route aliases', () {
    expect(module.handlesView('/channel/analytics/view'), isTrue);
    expect(module.handlesView('/auth/otp/channel/analytics/view'), isTrue);
    expect(module.handlesForward('/auth/channel/analytics/forward'), isTrue);
    expect(module.handlesStats('/auth/otp/channel/analytics/stats'), isTrue);
    expect(module.handlesView('/channel/analytics/stats'), isFalse);
  });
}
