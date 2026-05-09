import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/invite_link_models.dart';

void main() {
  group('XmoInviteLink', () {
    test('serializes and deserializes tracked invite links', () {
      final createdAt = DateTime.utc(2026, 5, 6, 10, 30);
      final expiresAt = DateTime.utc(2026, 5, 7);
      final link = XmoInviteLink(
        linkId: 'invite-1',
        url: 'https://matrix.to/#/!abc%3Alocalhost?xmo_invite=invite-1',
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
}
