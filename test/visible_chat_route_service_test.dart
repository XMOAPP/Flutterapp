import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/visible_chat_route_service.dart';

void main() {
  test('an older chat route cannot clear the newer visible chat', () {
    final service = VisibleChatRouteService.instance;
    final olderRoute = Object();
    final newerRoute = Object();

    service.show(olderRoute, '!older:example.org');
    service.show(newerRoute, '!newer:example.org');
    service.hide(olderRoute);

    expect(service.roomId.value, '!newer:example.org');

    service.hide(newerRoute);
    expect(service.roomId.value, isNull);
  });
}
