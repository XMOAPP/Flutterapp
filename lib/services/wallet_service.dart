import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

// Conditional import for web-only functionality
import 'wallet_service_stub.dart'
    if (dart.library.js_interop) 'wallet_service_web.dart';

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
    if (!kIsWeb) {
      return [];
    }
    return detectWalletsImpl();
  }

  // ── Connect wallet ─────────────────────────────────────────────────────────

  /// Connects to a browser wallet (MetaMask, Brave, Coinbase, etc.).
  /// Returns the wallet address on success.
  Future<String> connectWallet(String walletName) async {
    if (!kIsWeb) {
      throw UnsupportedError('Wallet auth is only supported on Web.');
    }

    _connectedAddress = await connectWalletImpl(walletName);
    return _connectedAddress!;
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

    return await signMessageImpl(message);
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  void disconnect() {
    disconnectImpl();
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
