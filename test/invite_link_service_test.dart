import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/invite_link_service.dart';

void main() {
  const token = 'Abcdefghijklmnopqrstuvwxyz0123456789_-ABCD';

  group('InviteLinkService secure links', () {
    test('extracts tokens from canonical HTTPS links', () {
      expect(
        InviteLinkService.extractSecureToken(
          'https://xmo.dpdns.org/join/$token',
        ),
        token,
      );
    });

    test('extracts tokens from the XMO fallback scheme', () {
      expect(
        InviteLinkService.extractSecureToken('xmo://join/$token'),
        token,
      );
    });

    test('rejects another host and malformed tokens', () {
      expect(
        InviteLinkService.extractSecureToken(
          'https://example.com/join/$token',
        ),
        isNull,
      );
      expect(
        InviteLinkService.extractSecureToken(
          'https://xmo.dpdns.org/join/short-token',
        ),
        isNull,
      );
      expect(
        InviteLinkService.extractSecureToken(
          'https://xmo.dpdns.org/join/${token}extra/path',
        ),
        isNull,
      );
    });

    test('recognizes secure and legacy invite links only', () {
      final service = InviteLinkService.instance;
      expect(service.isInviteLink('https://xmo.dpdns.org/join/$token'), isTrue);
      expect(
        service.isInviteLink('https://matrix.to/#/%21abc%3Alocalhost'),
        isTrue,
      );
      expect(
          service.isInviteLink('https://example.com/not-an-invite'), isFalse);
    });
  });
}
