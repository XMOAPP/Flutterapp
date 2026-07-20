import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/call_link_service.dart';
import 'package:xmo/services/wallet_deep_link_handler.dart';

void main() {
  group('CallLinkService', () {
    const roomId = '!room:xmo-matrix.example.org';

    test('accepts strict custom and HTTPS call links', () {
      expect(
        CallLinkService.roomIdFromLink(
          'xmo://call?room_id=${Uri.encodeQueryComponent(roomId)}',
        ),
        roomId,
      );
      expect(
        CallLinkService.roomIdFromLink(
          'https://xmo.dpdns.org/call/${Uri.encodeComponent(roomId)}',
        ),
        roomId,
      );
    });

    test('rejects insecure hosts, unexpected parameters, and invalid IDs', () {
      expect(
        CallLinkService.roomIdFromLink(
          'http://xmo.dpdns.org/call/${Uri.encodeComponent(roomId)}',
        ),
        isNull,
      );
      expect(
        CallLinkService.roomIdFromLink(
          'https://attacker.example/call/${Uri.encodeComponent(roomId)}',
        ),
        isNull,
      );
      expect(
        CallLinkService.roomIdFromLink(
          'xmo://call?room_id=${Uri.encodeQueryComponent(roomId)}&next=bad',
        ),
        isNull,
      );
      expect(CallLinkService.roomIdFromLink('xmo://call?room_id=room'), isNull);
    });
  });

  group('WalletDeepLinkHandler', () {
    test('accepts only XMO wallet callbacks and WalletConnect URIs', () {
      expect(
        WalletDeepLinkHandler.isSupportedWalletLink('xmo://wallet'),
        isTrue,
      );
      expect(
        WalletDeepLinkHandler.isSupportedWalletLink(
          'wc:topic@2?relay-protocol=irn&symKey=abc',
        ),
        isTrue,
      );
      expect(
        WalletDeepLinkHandler.isSupportedWalletLink(
          'https://attacker.example/walletconnect?value=wc%3Atopic',
        ),
        isFalse,
      );
      expect(
        WalletDeepLinkHandler.isSupportedWalletLink('xmo://wallet/extra'),
        isFalse,
      );
    });
  });
}
