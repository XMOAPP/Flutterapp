part of xmo_auth_server;

Future<void> _createWalletNonce(HttpRequest request) async {
  final body = await _readJson(request);

  try {
    final challenge = _walletAuthService.createChallenge(
      username: body['username']?.toString() ?? '',
      address: body['address']?.toString() ?? '',
      mode: body['mode']?.toString() ?? 'login',
      chainId: body['chainId']?.toString() ?? '1',
      walletType: body['walletType']?.toString() ?? 'evm',
    );
    await _json(request, HttpStatus.ok, challenge.toJson());
  } on WalletAuthException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  }
}

Future<void> _verifyWalletSignature(HttpRequest request) async {
  final body = await _readJson(request);

  try {
    final verification = await _walletAuthService.verify(
      username: body['username']?.toString() ?? '',
      address: body['address']?.toString() ?? '',
      message: body['message']?.toString() ?? '',
      signature: body['signature']?.toString() ?? '',
      mode: body['mode']?.toString() ?? 'login',
      walletType: body['walletType']?.toString() ?? 'evm',
    );
    logInfo('wallet_auth_verified', {
      'usernameHash': verification.username.hashCode,
      'walletHash': verification.address.hashCode,
    });
    await _json(request, HttpStatus.ok, verification.toJson());
  } on WalletAuthException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  }
}
