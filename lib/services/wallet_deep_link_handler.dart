import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'call_link_service.dart';

class WalletDeepLinkHandler {
  static const _methodChannel = MethodChannel('com.xmo.xmo/wallet_methods');
  static const _eventChannel = EventChannel('com.xmo.xmo/wallet_events');

  static IReownAppKitModal? _appKitModal;
  static bool _listening = false;

  static void initListener() {
    if (kIsWeb || _listening) return;
    _listening = true;
    _eventChannel.receiveBroadcastStream().listen(
          _onLink,
          onError: (error) => debugPrint('[WalletDeepLink] $error'),
        );
  }

  static void attach(IReownAppKitModal appKitModal) {
    if (kIsWeb) return;
    _appKitModal = appKitModal;
  }

  static Future<void> checkInitialLink() async {
    if (kIsWeb) return;
    try {
      final link = await _methodChannel.invokeMethod<String>('initialLink');
      if (link != null && link.isNotEmpty) {
        await _onLink(link);
      }
    } catch (e) {
      debugPrint('[WalletDeepLink] initial link failed: $e');
    }
  }

  static Future<void> _onLink(dynamic link) async {
    final value = link?.toString();
    if (value == null || value.isEmpty) return;

    final handled = await _appKitModal?.dispatchEnvelope(value) ?? false;
    if (!handled && await CallLinkService.instance.handleLink(value)) {
      return;
    }
    if (!handled) {
      debugPrint('[WalletDeepLink] Link was not handled by AppKit: $value');
    }
  }
}
