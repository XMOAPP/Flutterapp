import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'call_link_service.dart';

class WalletDeepLinkHandler {
  static const _methodChannel = MethodChannel('com.xmo.xmo/wallet_methods');
  static const _eventChannel = EventChannel('com.xmo.xmo/wallet_events');

  static IReownAppKitModal? _appKitModal;
  static bool _listening = false;
  static final List<String> _pendingWalletLinks = <String>[];

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
    Future<void>.microtask(_flushPendingWalletLinks);
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

    final appKitModal = _appKitModal;
    if (appKitModal == null && isSupportedWalletLink(value)) {
      _queueWalletLink(value);
      return;
    }

    final handled = await appKitModal?.dispatchEnvelope(value) ?? false;
    if (!handled && await CallLinkService.instance.handleLink(value)) {
      return;
    }
    if (!handled && isSupportedWalletLink(value)) {
      _queueWalletLink(value);
      return;
    }
    if (!handled) {
      debugPrint('[WalletDeepLink] Link was not handled by AppKit: $value');
    }
  }

  static Future<void> _flushPendingWalletLinks() async {
    final appKitModal = _appKitModal;
    if (appKitModal == null || _pendingWalletLinks.isEmpty) return;

    final links = List<String>.from(_pendingWalletLinks);
    _pendingWalletLinks.clear();
    for (final link in links) {
      final handled = await appKitModal.dispatchEnvelope(link);
      if (!handled) {
        _queueWalletLink(link);
      }
    }
  }

  static void _queueWalletLink(String link) {
    if (_pendingWalletLinks.contains(link)) return;
    _pendingWalletLinks
      ..clear()
      ..add(link);
    debugPrint('[WalletDeepLink] Queued wallet link until AppKit is ready');
  }

  static bool isSupportedWalletLink(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.userInfo.isNotEmpty || uri.hasPort) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'wc') return value.trim().length > 3;
    return scheme == 'xmo' &&
        uri.host.toLowerCase() == 'wallet' &&
        (uri.path.isEmpty || uri.path == '/') &&
        uri.fragment.isEmpty;
  }
}
