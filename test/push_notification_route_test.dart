import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/push_notification_service.dart';

void main() {
  group('PushNotificationRoute', () {
    test('normalizes Matrix room and event routing identifiers', () {
      const route = PushNotificationRoute({
        'room_id': '!room:example.org',
        'eventId': r'$event',
        'sender_display_name': 'Alice',
      });

      expect(route.roomId, '!room:example.org');
      expect(route.eventId, r'$event');
      expect(route.sender, 'Alice');
      expect(route.isCall, isFalse);
    });

    test('hides a full Matrix sender ID from notification labels', () {
      const route = PushNotificationRoute({
        'sender': '@hunter:xmo.example.com',
      });

      expect(route.sender, 'Hunter');
    });

    test('recognizes direct-call payloads', () {
      const route = PushNotificationRoute({
        'event_type': 'm.call.invite',
        'call_id': 'call-1',
        'call_type': 'voice',
      });

      expect(route.isCall, isTrue);
      expect(route.callId, 'call-1');
      expect(route.callType, 'voice');
    });

    test('recognizes group-call payloads from Matrix state events', () {
      const route = PushNotificationRoute({
        'type': 'org.matrix.msc3401.call.member',
        'group_call_id': 'group-1',
      });

      expect(route.isCall, isTrue);
      expect(route.callId, 'group-1');
    });

    test('normalizes Matrix and camelCase call identifier variants', () {
      const route = PushNotificationRoute({
        'roomId': '!room:example.org',
        'event': r'$event',
        'm.call_id': 'matrix-call',
        'callType': 'm.video',
      });

      expect(route.roomId, '!room:example.org');
      expect(route.eventId, r'$event');
      expect(route.callId, 'matrix-call');
      expect(route.callType, 'm.video');
      expect(route.isCall, isFalse);
    });

    test('recognizes explicit group-call id payloads', () {
      const route = PushNotificationRoute({
        'room_id': '!room:example.org',
        'groupCallId': 'group-2',
        'group_call': '1',
      });

      expect(route.isCall, isTrue);
      expect(route.isGroupCall, isTrue);
      expect(route.callId, 'group-2');
    });

    test('accepts the explicit XMO call marker', () {
      const route = PushNotificationRoute({'xmo_push_type': 'call'});
      expect(route.isCall, isTrue);
    });
  });
}
