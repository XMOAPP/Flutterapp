/// Stub implementation for non-web platforms
library;

List<String> detectWalletsImpl() {
  throw UnsupportedError('Wallet detection is only supported on Web');
}

Future<String> connectWalletImpl(String walletName) async {
  throw UnsupportedError('Wallet connection is only supported on Web');
}

Future<String> signMessageImpl(String message) async {
  throw UnsupportedError('Wallet signing is only supported on Web');
}

void disconnectImpl() {
  throw UnsupportedError('Wallet disconnect is only supported on Web');
}
