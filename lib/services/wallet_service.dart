import 'dart:async';
import 'dart:js' as js;
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Handles Web3 wallet authentication via the xmoWallet JS bridge.
/// Supports MetaMask, Brave Wallet, Coinbase Wallet, and any EIP-1193 wallet.
class WalletService {
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal();

  String? _connectedAddress;
  String? get connectedAddress => _connectedAddress;
  bool get isConnected => _connectedAddress != null;

  // ── Detect available wallets ───────────────────────────────────────────────

  /// Returns a list of wallet names available in the browser.
  List<String> detectWallets() {
    if (!kIsWeb) return [];
    try {
      final bridge = js.context['xmoWallet'] as js.JsObject;
      final result = bridge.callMethod('detectWallets', []) as String;
      // Parse JSON array of wallet names
      return result
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('WalletService.detectWallets error: $e');
      return ['WalletConnect'];
    }
  }

  // ── Connect wallet ─────────────────────────────────────────────────────────

  /// Connects to a browser wallet (MetaMask, Brave, Coinbase, etc.).
  /// Returns the wallet address on success.
  Future<String> connectWallet(String walletName) async {
    if (!kIsWeb) throw UnsupportedError('Wallet auth is only supported on Web.');

    final completer = Completer<String>();
    try {
      final bridge = js.context['xmoWallet'] as js.JsObject;
      final promise = bridge.callMethod('connectBrowserWallet', [walletName]);

      js.JsObject.fromBrowserObject(promise)
        ..callMethod('then', [
          js.allowInterop((account) {
            _connectedAddress = account.toString();
            if (!completer.isCompleted) completer.complete(_connectedAddress!);
          })
        ])
        ..callMethod('catch', [
          js.allowInterop((err) {
            if (!completer.isCompleted) {
              completer.completeError(err.toString());
            }
          })
        ]);
    } catch (e) {
      completer.completeError(e.toString());
    }
    return completer.future;
  }

  // ── Sign authentication message ────────────────────────────────────────────

  /// Generates and signs an XMO login message.
  /// Returns the signature if the user approves in their wallet.
  Future<String> signAuthMessage(String username) async {
    if (_connectedAddress == null) throw Exception('No wallet connected.');

    final nonce = _generateNonce();
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final message =
        'XMO wants you to sign in with your wallet.\n\n'
        'Username: $username\n'
        'Wallet: $_connectedAddress\n'
        'Nonce: $nonce\n'
        'Issued At: $timestamp\n\n'
        'This request will not trigger a blockchain transaction.';

    final completer = Completer<String>();
    try {
      final bridge = js.context['xmoWallet'] as js.JsObject;
      final promise = bridge.callMethod('signMessage', [message]);

      js.JsObject.fromBrowserObject(promise)
        ..callMethod('then', [
          js.allowInterop((sig) {
            if (!completer.isCompleted) completer.complete(sig.toString());
          })
        ])
        ..callMethod('catch', [
          js.allowInterop((err) {
            if (!completer.isCompleted) completer.completeError(err.toString());
          })
        ]);
    } catch (e) {
      completer.completeError(e.toString());
    }
    return completer.future;
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  void disconnect() {
    try {
      final bridge = js.context['xmoWallet'] as js.JsObject;
      bridge.callMethod('disconnect', []);
    } catch (_) {}
    _connectedAddress = null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Short wallet address: 0x1234...abcd
  String shortAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  String _generateNonce() {
    final rand = Random.secure();
    return List.generate(8, (_) => rand.nextInt(16).toRadixString(16)).join();
  }
}
