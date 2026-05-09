import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

/// Web implementation of wallet service using dart:js_interop

@JS('xmoWallet')
external JSObject? get xmoWallet;

@JS()
@staticInterop
class XmoWalletBridge {}

extension XmoWalletBridgeExtension on XmoWalletBridge {
  external JSPromise detectWallets();
  external JSPromise connectBrowserWallet(String walletName);
  external JSPromise signMessage(String message);
  external void disconnect();
}

List<String> detectWalletsImpl() {
  try {
    final bridge = xmoWallet;
    if (bridge == null) {
      debugPrint('xmoWallet bridge not found');
      return ['WalletConnect'];
    }
    
    // Return default wallets (bridge.detectWallets() would be async)
    return ['MetaMask', 'Brave Wallet', 'Coinbase Wallet', 'WalletConnect'];
  } catch (e) {
    debugPrint('WalletService.detectWallets error: $e');
    return ['WalletConnect'];
  }
}

Future<String> connectWalletImpl(String walletName) async {
  final completer = Completer<String>();
  
  try {
    final bridge = xmoWallet;
    if (bridge == null) {
      throw Exception('xmoWallet bridge not found');
    }
    
    final walletBridge = bridge as XmoWalletBridge;
    final promise = walletBridge.connectBrowserWallet(walletName);
    
    promise.toDart.then((result) {
      final account = (result as JSString).toDart;
      completer.complete(account);
    }).catchError((error) {
      completer.completeError(error.toString());
    });
  } catch (e) {
    completer.completeError(e.toString());
  }
  
  return completer.future;
}

Future<String> signMessageImpl(String message) async {
  final completer = Completer<String>();
  
  try {
    final bridge = xmoWallet;
    if (bridge == null) {
      throw Exception('xmoWallet bridge not found');
    }
    
    final walletBridge = bridge as XmoWalletBridge;
    final promise = walletBridge.signMessage(message);
    
    promise.toDart.then((result) {
      final signature = (result as JSString).toDart;
      completer.complete(signature);
    }).catchError((error) {
      completer.completeError(error.toString());
    });
  } catch (e) {
    completer.completeError(e.toString());
  }
  
  return completer.future;
}

void disconnectImpl() {
  try {
    final bridge = xmoWallet;
    if (bridge != null) {
      final walletBridge = bridge as XmoWalletBridge;
      walletBridge.disconnect();
    }
  } catch (e) {
    debugPrint('Disconnect error: $e');
  }
}
