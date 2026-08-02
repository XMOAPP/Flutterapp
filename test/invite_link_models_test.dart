import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/invite_link_models.dart';

void main() {
  group('XmoInviteLink', () {
    test('serializes and deserializes tracked invite links', () {
      final createdAt = DateTime.utc(2026, 5, 6, 10, 30);
      final expiresAt = DateTime.utc(2026, 5, 7);
      final link = XmoInviteLink(
        linkId: 'invite-1',
        url:
            'https://xmo.dpdns.org/join/abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG',
        roomId: '!abc:localhost',
        createdAt: createdAt,
        expiresAt: expiresAt,
        usedCount: 2,
        createdBy: '@alice:localhost',
        isActive: false,
      );

      final decoded = XmoInviteLink.fromJson(link.toJson());

      expect(decoded.linkId, 'invite-1');
      expect(decoded.url, link.url);
      expect(decoded.roomId, '!abc:localhost');
      expect(decoded.createdAt, createdAt);
      expect(decoded.expiresAt, expiresAt);
      expect(decoded.usedCount, 2);
      expect(decoded.createdBy, '@alice:localhost');
      expect(decoded.isActive, isFalse);
      expect(decoded.canBeUsed, isFalse);
    });
  });

  group('XmoInvitePreview', () {
    test('parses the public invite snapshot', () {
      final preview = XmoInvitePreview.fromJson({
        'name': 'Launch group',
        'type': 'group',
        'topic': 'Release coordination',
        'memberCount': 12,
        'joinMode': 'knock',
        'expiresAt': '2026-08-01T00:00:00Z',
      });

      expect(preview.name, 'Launch group');
      expect(preview.type, 'group');
      expect(preview.topic, 'Release coordination');
      expect(preview.memberCount, 12);
      expect(preview.requiresApproval, isTrue);
    });

    test('rejects unsupported room types and join modes', () {
      expect(
        () => XmoInvitePreview.fromJson({
          'name': 'Invalid',
          'type': 'space',
          'memberCount': 1,
          'joinMode': 'invite',
          'expiresAt': '2026-08-01T00:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('requires a valid expiry timestamp', () {
      expect(
        () => XmoInvitePreview.fromJson({
          'name': 'Invalid',
          'type': 'channel',
          'memberCount': 1,
          'joinMode': 'join',
        }),
        throwsFormatException,
      );
    });
  });
}
