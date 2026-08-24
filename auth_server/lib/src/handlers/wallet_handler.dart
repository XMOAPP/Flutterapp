part of xmo_auth_server;

bool get _walletAccountsConfigured =>
    _walletAuthService.config.isConfigured && _walletAccountStoreReady;

/// Returns the authenticated account kind for Security settings.
///
/// A client must not be able to select its own account type, so the Matrix
/// access token is resolved through Synapse before consulting the wallet DB.
Future<void> _getWalletSession(HttpRequest request) async {
  if (!_walletAccountsConfigured) {
    await _walletUnavailable(request);
    return;
  }

  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'error': 'An active XMO session is required',
    });
    return;
  }

  try {
    final userId = await _userDirectoryWhoami(token);
    final account = await _walletAccountStore.findActiveAccountByMatrixUserId(
      userId,
    );
    await _json(request, HttpStatus.ok, {
      'success': true,
      'accountType': account == null ? 'standard' : 'wallet',
      if (account != null)
        'wallet': {
          'type': account.walletType,
          'address': account.walletAddress,
          'chainId': account.chainId,
        },
    });
  } on _BadRequestException catch (error) {
    await _json(request, HttpStatus.unauthorized, {'error': error.message});
  } catch (error, stackTrace) {
    _logger.error('wallet_session_lookup_failed', error, stackTrace);
    await _json(request, HttpStatus.badGateway, {
      'error': 'Could not check account security settings',
    });
  }
}

Future<void> _getWalletAccount(HttpRequest request) async {
  if (!_walletAccountsConfigured) {
    await _walletUnavailable(request);
    return;
  }
  final body = await _readJson(request);
  try {
    final walletType = WalletAuthService.normalizeWalletType(
      body['walletType']?.toString() ?? 'evm',
    );
    final address = WalletAuthService.normalizeAddress(
      body['address']?.toString() ?? '',
      walletType: walletType,
    );
    final account = await _walletAccountStore.findAccount(
      walletType: walletType,
      walletAddress: address,
      includePending: true,
    );
    await _json(request, HttpStatus.ok, {
      'success': true,
      'exists': account != null,
      if (account != null) 'username': account.username,
    });
  } on WalletAuthException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  }
}

Future<void> _checkWalletUsernameAvailability(HttpRequest request) async {
  if (!_walletAccountsConfigured) {
    await _walletUnavailable(request);
    return;
  }
  final body = await _readJson(request);
  try {
    final username = WalletAuthService.normalizeUsername(
      body['username']?.toString() ?? '',
    );
    await _json(request, HttpStatus.ok, {
      'success': true,
      'available': await _isWalletUsernameAvailable(username),
    });
  } on WalletAuthException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  }
}

Future<void> _createWalletNonce(HttpRequest request) async {
  if (!_walletAccountsConfigured) {
    await _walletUnavailable(request);
    return;
  }
  final body = await _readJson(request);

  try {
    final walletType = WalletAuthService.normalizeWalletType(
      body['walletType']?.toString() ?? 'evm',
    );
    final address = WalletAuthService.normalizeAddress(
      body['address']?.toString() ?? '',
      walletType: walletType,
    );
    final requestedMode = body['mode']?.toString() == 'create'
        ? 'create'
        : 'login';
    final existing = await _walletAccountStore.findAccount(
      walletType: walletType,
      walletAddress: address,
      includePending: true,
    );

    late final String username;
    late final String challengeMode;
    if (existing != null) {
      username = existing.username;
      challengeMode = existing.isActive ? 'login' : 'create';
    } else if (requestedMode == 'login') {
      await _json(request, HttpStatus.notFound, {
        'error': 'This wallet does not have an XMO account yet.',
      });
      return;
    } else {
      username = WalletAuthService.normalizeUsername(
        body['username']?.toString() ?? '',
      );
      if (!await _isWalletUsernameAvailable(username)) {
        await _json(request, HttpStatus.conflict, {
          'error': 'Username already taken',
        });
        return;
      }
      challengeMode = 'create';
    }

    final challenge = _walletAuthService.createChallenge(
      username: username,
      address: address,
      mode: challengeMode,
      chainId: body['chainId']?.toString() ?? '1',
      walletType: walletType,
    );
    await _walletAccountStore.saveChallenge(
      WalletStoredChallenge(
        nonce: challenge.nonce,
        username: challenge.username,
        walletType: challenge.walletType,
        walletAddress: challenge.address,
        chainId: challenge.chainId,
        mode: challenge.mode,
        message: challenge.message,
        expiresAt: challenge.expiresAt,
      ),
    );
    await _json(request, HttpStatus.ok, challenge.toJson());
  } on WalletAuthException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  }
}

Future<void> _verifyWalletSignature(HttpRequest request) async {
  if (!_walletAccountsConfigured) {
    await _walletUnavailable(request);
    return;
  }
  final body = await _readJson(request);

  try {
    final message = body['message']?.toString() ?? '';
    final suppliedNonce = body['nonce']?.toString().trim() ?? '';
    final nonce = suppliedNonce.isNotEmpty
        ? suppliedNonce
        : _walletMessageField(message, 'Nonce');
    final stored = await _walletAccountStore.consumeChallenge(nonce);
    if (stored == null) {
      throw const WalletAuthException(
        'Wallet challenge expired or was already used. Try again.',
      );
    }
    final challenge = WalletAuthChallenge(
      username: stored.username,
      address: stored.walletAddress,
      mode: stored.mode,
      walletType: stored.walletType,
      chainId: stored.chainId,
      nonce: stored.nonce,
      message: stored.message,
      expiresAt: stored.expiresAt,
    );
    await _walletAuthService.verify(
      challenge: challenge,
      username: body['username']?.toString() ?? stored.username,
      address: body['address']?.toString() ?? '',
      message: message,
      signature: body['signature']?.toString() ?? '',
      mode: body['mode']?.toString() ?? stored.mode,
      walletType: body['walletType']?.toString() ?? stored.walletType,
    );

    var account = await _walletAccountStore.findAccount(
      walletType: stored.walletType,
      walletAddress: stored.walletAddress,
      includePending: true,
    );
    if (stored.mode == 'create') {
      if (account != null && account.isActive) {
        throw const WalletAuthException(
          'This wallet already has an XMO account.',
        );
      }
      if (account == null) {
        if (!await _isWalletUsernameAvailable(stored.username)) {
          throw const WalletAuthException('Username already taken');
        }
        account = WalletAccount(
          walletType: stored.walletType,
          walletAddress: stored.walletAddress,
          username: stored.username,
          matrixUserId: _matrixUserId(stored.username),
          chainId: stored.chainId,
          status: 'pending',
          createdAt: DateTime.now().toUtc(),
        );
        try {
          await _walletAccountStore.reserveAccount(account);
        } on WalletAccountConflict {
          throw const WalletAuthException(
            'This wallet or username already has an XMO account.',
          );
        }
      } else if (account.username != stored.username) {
        throw const WalletAuthException('Wallet account does not match.');
      }

      // Keep the reservation if either operation fails. A retry with the same
      // wallet can safely finish activation if Synapse already accepted it.
      await _ensurePasswordlessWalletMatrixUser(stored.username);
      await _walletAccountStore.activateAccount(
        walletType: stored.walletType,
        walletAddress: stored.walletAddress,
      );
    } else if (account == null || account.username != stored.username) {
      throw const WalletAuthException('Wallet account was not found.');
    }

    final token = _walletAuthService.issueMatrixLoginToken(account.username);
    logInfo('wallet_auth_verified', {
      'mode': stored.mode,
      'usernameHash': account.username.hashCode,
      'walletHash': account.walletAddress.hashCode,
    });
    await _json(request, HttpStatus.ok, {
      'success': true,
      'username': account.username,
      'address': account.walletAddress,
      'walletType': account.walletType,
      'matrixLoginToken': token,
    });
  } on WalletAuthException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  } catch (error, stackTrace) {
    _logger.error('wallet_auth_failed', error, stackTrace);
    await _json(request, HttpStatus.badGateway, {
      'error': 'Wallet authentication could not be completed. Please retry.',
    });
  }
}

Future<bool> _isWalletUsernameAvailable(String username) async {
  if (await _walletAccountStore.usernameExists(username)) return false;
  if (await _authentikFindUser(username) != null) return false;
  final response = await _synapseRequest(
    method: 'GET',
    pathSegments: ['_synapse', 'admin', 'v2', 'users', _matrixUserId(username)],
  );
  if (response.statusCode == HttpStatus.notFound) return true;
  if (response.statusCode == HttpStatus.ok) return false;
  throw HttpException('Synapse user lookup failed: ${response.statusCode}');
}

Future<void> _ensurePasswordlessWalletMatrixUser(String username) async {
  final userId = _matrixUserId(username);
  final existing = await _synapseRequest(
    method: 'GET',
    pathSegments: ['_synapse', 'admin', 'v2', 'users', userId],
  );
  if (existing.statusCode == HttpStatus.ok) {
    return;
  }
  if (existing.statusCode != HttpStatus.notFound) {
    throw HttpException('Synapse user lookup failed: ${existing.statusCode}');
  }
  await _synapseUpdateUser(userId, {
    'displayname': username,
    'admin': false,
    'deactivated': false,
  });
}

String _walletMessageField(String message, String field) {
  final prefix = '$field: ';
  for (final line in const LineSplitter().convert(message)) {
    if (line.startsWith(prefix)) return line.substring(prefix.length).trim();
  }
  throw WalletAuthException('Missing wallet message field: $field');
}

Future<void> _walletUnavailable(HttpRequest request) => _json(
  request,
  HttpStatus.serviceUnavailable,
  {'error': 'Wallet account service is not configured'},
);
