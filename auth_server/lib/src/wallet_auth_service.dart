import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto_graphy;
import 'package:web3dart/web3dart.dart';

class WalletAuthConfig {
  const WalletAuthConfig({
    required this.jwtSecret,
    required this.jwtIssuer,
    required this.jwtAudience,
    required this.domain,
    required this.uri,
    required this.statement,
  });

  factory WalletAuthConfig.fromEnvironment(Map<String, String> env) {
    return WalletAuthConfig(
      jwtSecret: env['XMO_WALLET_JWT_SECRET'] ?? '',
      jwtIssuer: env['XMO_WALLET_JWT_ISSUER'] ?? 'xmo-wallet-auth',
      jwtAudience: env['XMO_WALLET_JWT_AUDIENCE'] ?? 'xmo-matrix',
      domain: env['XMO_WALLET_AUTH_DOMAIN'] ??
          'xmo-matrix.centralindia.cloudapp.azure.com',
      uri: env['XMO_WALLET_AUTH_URI'] ??
          'https://xmo-matrix.centralindia.cloudapp.azure.com',
      statement: env['XMO_WALLET_AUTH_STATEMENT'] ??
          'Sign in to XMO Messenger. This request will not trigger a blockchain transaction.',
    );
  }

  final String jwtSecret;
  final String jwtIssuer;
  final String jwtAudience;
  final String domain;
  final String uri;
  final String statement;

  bool get isConfigured =>
      jwtSecret.trim().length >= 32 &&
      jwtIssuer.trim().isNotEmpty &&
      jwtAudience.trim().isNotEmpty;
}

class WalletAuthService {
  WalletAuthService({
    required this.config,
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? (() => DateTime.now().toUtc()),
        _random = random ?? Random.secure();

  final WalletAuthConfig config;
  final DateTime Function() _now;
  final Random _random;
  static const challengeTtl = Duration(minutes: 5);
  static const loginTokenTtl = Duration(seconds: 60);

  WalletAuthChallenge createChallenge({
    required String username,
    required String address,
    required String mode,
    String chainId = '1',
    String walletType = 'evm',
  }) {
    if (!config.isConfigured) {
      throw const WalletAuthException(
          'Wallet authentication is not configured');
    }

    final cleanUsername = normalizeUsername(username);
    final cleanWalletType = normalizeWalletType(walletType);
    final cleanAddress = normalizeAddress(address, walletType: cleanWalletType);
    final cleanMode = mode == 'create' ? 'create' : 'login';
    final cleanChainId =
        _normalizeChainId(chainId, walletType: cleanWalletType);
    final issuedAt = _now();
    final expiresAt = issuedAt.add(challengeTtl);
    final nonce = _nonce();
    final message = _buildMessage(
      username: cleanUsername,
      address: cleanAddress,
      mode: cleanMode,
      walletType: cleanWalletType,
      chainId: cleanChainId,
      nonce: nonce,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
    return WalletAuthChallenge(
      username: cleanUsername,
      address: cleanAddress,
      mode: cleanMode,
      walletType: cleanWalletType,
      chainId: cleanChainId,
      nonce: nonce,
      message: message,
      expiresAt: expiresAt,
    );
  }

  Future<void> verify({
    required WalletAuthChallenge challenge,
    required String username,
    required String address,
    required String message,
    required String signature,
    required String mode,
    String walletType = 'evm',
  }) async {
    if (!config.isConfigured) {
      throw const WalletAuthException(
          'Wallet authentication is not configured');
    }

    final cleanUsername = normalizeUsername(username);
    final cleanWalletType = normalizeWalletType(walletType);
    final cleanAddress = normalizeAddress(address, walletType: cleanWalletType);
    final cleanMode = mode == 'create' ? 'create' : 'login';
    if (_now().isAfter(challenge.expiresAt)) {
      throw const WalletAuthException('Wallet challenge expired. Try again.');
    }
    if (challenge.username != cleanUsername ||
        challenge.address != cleanAddress ||
        challenge.mode != cleanMode ||
        challenge.walletType != cleanWalletType ||
        challenge.message != message) {
      throw const WalletAuthException('Wallet challenge does not match.');
    }

    if (cleanWalletType == WalletAuthTypes.evm) {
      final recoveredAddress = recoverPersonalSignAddress(
        message: message,
        signature: signature,
      );
      if (recoveredAddress != cleanAddress) {
        throw const WalletAuthException(
            'Wallet signature verification failed.');
      }
    } else if (cleanWalletType == WalletAuthTypes.solana) {
      final verified = await verifySolanaSignature(
        message: message,
        address: cleanAddress,
        signature: signature,
      );
      if (!verified) {
        throw const WalletAuthException(
            'Wallet signature verification failed.');
      }
    }
  }

  String issueMatrixLoginToken(String username) {
    if (!config.isConfigured) {
      throw const WalletAuthException(
        'Wallet authentication is not configured',
      );
    }
    final now = _now();
    final header = {'alg': 'HS256', 'typ': 'JWT'};
    final claims = {
      'sub': normalizeUsername(username),
      'iss': config.jwtIssuer,
      'aud': config.jwtAudience,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'nbf': now.subtract(const Duration(seconds: 2)).millisecondsSinceEpoch ~/
          1000,
      'exp': now.add(loginTokenTtl).millisecondsSinceEpoch ~/ 1000,
      'jti': _nonce(),
    };
    final encodedHeader = _base64UrlJson(header);
    final encodedClaims = _base64UrlJson(claims);
    final signingInput = '$encodedHeader.$encodedClaims';
    final signature = Hmac(sha256, utf8.encode(config.jwtSecret))
        .convert(utf8.encode(signingInput));
    return '$signingInput.${base64UrlEncode(signature.bytes).replaceAll('=', '')}';
  }

  String _base64UrlJson(Map<String, Object> value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  static String normalizeUsername(String value) {
    final clean = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]{3,32}$').hasMatch(clean)) {
      throw const WalletAuthException(
        'Username must be 3-32 lowercase letters or numbers',
      );
    }
    return clean;
  }

  static String normalizeWalletType(String value) {
    final clean = value.trim().toLowerCase();
    if (clean == WalletAuthTypes.evm || clean == WalletAuthTypes.solana) {
      return clean;
    }
    throw const WalletAuthException('Unsupported wallet type');
  }

  static String normalizeAddress(
    String value, {
    String walletType = WalletAuthTypes.evm,
  }) {
    final clean = value.trim().toLowerCase();
    final cleanWalletType = normalizeWalletType(walletType);
    if (cleanWalletType == WalletAuthTypes.evm) {
      if (!RegExp(r'^0x[a-f0-9]{40}$').hasMatch(clean)) {
        throw const WalletAuthException('Invalid wallet address');
      }
      return clean;
    }

    try {
      final decoded = base58.decode(value.trim());
      if (decoded.length != 32) {
        throw const WalletAuthException('Invalid Solana wallet address');
      }
      return value.trim();
    } on WalletAuthException {
      rethrow;
    } catch (_) {
      throw const WalletAuthException('Invalid Solana wallet address');
    }
  }

  static String recoverPersonalSignAddress({
    required String message,
    required String signature,
  }) {
    try {
      final signatureBytes = hexToBytes(signature);
      if (signatureBytes.length != 65) {
        throw const WalletAuthException('Invalid wallet signature');
      }

      var v = signatureBytes[64];
      if (v < 27) v += 27;
      final sig = MsgSignature(
        bytesToUnsignedInt(signatureBytes.sublist(0, 32)),
        bytesToUnsignedInt(signatureBytes.sublist(32, 64)),
        v,
      );
      final messageBytes = Uint8List.fromList(utf8.encode(message));
      final prefix =
          utf8.encode('\u0019Ethereum Signed Message:\n${messageBytes.length}');
      final hash = keccak256(Uint8List.fromList([...prefix, ...messageBytes]));
      final recoveredPublicKey = _padLeft(ecRecover(hash, sig), 64);
      final recoveredAddress = publicKeyToAddress(recoveredPublicKey);
      return '0x${bytesToHex(recoveredAddress)}'.toLowerCase();
    } on WalletAuthException {
      rethrow;
    } catch (_) {
      throw const WalletAuthException('Invalid wallet signature');
    }
  }

  static Future<bool> verifySolanaSignature({
    required String message,
    required String address,
    required String signature,
  }) async {
    try {
      final publicKeyBytes = base58.decode(address);
      final signatureBytes = _decodeSolanaSignature(signature);
      final publicKey = crypto_graphy.SimplePublicKey(
        publicKeyBytes,
        type: crypto_graphy.KeyPairType.ed25519,
      );
      final signatureObject = crypto_graphy.Signature(
        signatureBytes,
        publicKey: publicKey,
      );
      return crypto_graphy.Ed25519().verify(
        utf8.encode(message),
        signature: signatureObject,
      );
    } catch (_) {
      return false;
    }
  }

  static List<int> _decodeSolanaSignature(String signature) {
    final trimmed = signature.trim();
    if (trimmed.startsWith('0x')) {
      return hexToBytes(trimmed);
    }
    try {
      final decoded = base64Decode(trimmed);
      if (decoded.length == 64) return decoded;
    } catch (_) {
      // Try base58 next.
    }
    final decoded = base58.decode(trimmed);
    if (decoded.length != 64) {
      throw const WalletAuthException('Invalid wallet signature');
    }
    return decoded;
  }

  String _buildMessage({
    required String username,
    required String address,
    required String mode,
    required String walletType,
    required String chainId,
    required String nonce,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) {
    final accountLabel =
        walletType == WalletAuthTypes.solana ? 'Solana' : 'Ethereum';
    return '${config.domain} wants you to sign in with your $accountLabel account:\n'
        '$address\n\n'
        '${config.statement}\n\n'
        'URI: ${config.uri}\n'
        'Version: 1\n'
        'Chain ID: $chainId\n'
        'Nonce: $nonce\n'
        'Issued At: ${issuedAt.toIso8601String()}\n'
        'Expiration Time: ${expiresAt.toIso8601String()}\n'
        'Request ID: xmo-wallet-$mode-$username';
  }

  String _nonce() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      18,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  String _normalizeChainId(
    String chainId, {
    String walletType = WalletAuthTypes.evm,
  }) {
    final clean = chainId.trim();
    final cleanWalletType = normalizeWalletType(walletType);
    if (cleanWalletType == WalletAuthTypes.solana) {
      return clean.startsWith('solana:') ? clean : 'solana:$clean';
    }
    final value = clean.startsWith('eip155:') ? clean.substring(7) : clean;
    return RegExp(r'^[0-9]+$').hasMatch(value) ? value : '1';
  }

  static Uint8List _padLeft(Uint8List bytes, int length) {
    if (bytes.length == length) return bytes;
    if (bytes.length > length) return bytes.sublist(bytes.length - length);
    return Uint8List(length)..setRange(length - bytes.length, length, bytes);
  }
}

class WalletAuthTypes {
  static const evm = 'evm';
  static const solana = 'solana';
}

class WalletAuthChallenge {
  const WalletAuthChallenge({
    required this.username,
    required this.address,
    required this.mode,
    required this.walletType,
    required this.chainId,
    required this.nonce,
    required this.message,
    required this.expiresAt,
  });

  final String username;
  final String address;
  final String mode;
  final String walletType;
  final String chainId;
  final String nonce;
  final String message;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
        'success': true,
        'username': username,
        'address': address,
        'mode': mode,
        'walletType': walletType,
        'chainId': chainId,
        'nonce': nonce,
        'message': message,
        'expiresAt': expiresAt.toIso8601String(),
      };
}

class WalletAuthException implements Exception {
  const WalletAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
