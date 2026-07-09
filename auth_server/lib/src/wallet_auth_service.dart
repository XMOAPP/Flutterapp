import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto_graphy;
import 'package:web3dart/web3dart.dart';

class WalletAuthConfig {
  const WalletAuthConfig({
    required this.secret,
    required this.domain,
    required this.uri,
    required this.statement,
  });

  factory WalletAuthConfig.fromEnvironment(Map<String, String> env) {
    return WalletAuthConfig(
      secret: env['XMO_WALLET_AUTH_SECRET'] ?? '',
      domain: env['XMO_WALLET_AUTH_DOMAIN'] ??
          'xmo-matrix.centralindia.cloudapp.azure.com',
      uri: env['XMO_WALLET_AUTH_URI'] ??
          'https://xmo-matrix.centralindia.cloudapp.azure.com',
      statement: env['XMO_WALLET_AUTH_STATEMENT'] ??
          'Sign in to XMO Messenger. This request will not trigger a blockchain transaction.',
    );
  }

  final String secret;
  final String domain;
  final String uri;
  final String statement;

  bool get isConfigured => secret.trim().length >= 32;
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
  final Map<String, WalletAuthChallenge> _challenges = {};

  static const challengeTtl = Duration(minutes: 5);

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
    final challenge = WalletAuthChallenge(
      username: cleanUsername,
      address: cleanAddress,
      mode: cleanMode,
      walletType: cleanWalletType,
      chainId: cleanChainId,
      nonce: nonce,
      message: message,
      expiresAt: expiresAt,
    );
    _challenges[nonce] = challenge;
    _pruneExpired();
    return challenge;
  }

  Future<WalletAuthVerification> verify({
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
    final nonce = _extractField(message, 'Nonce');
    final challenge = _challenges[nonce];

    if (challenge == null) {
      throw const WalletAuthException('Wallet challenge expired. Try again.');
    }
    if (_now().isAfter(challenge.expiresAt)) {
      _challenges.remove(nonce);
      throw const WalletAuthException('Wallet challenge expired. Try again.');
    }
    if (challenge.used) {
      throw const WalletAuthException('Wallet challenge was already used.');
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

    challenge.used = true;
    return WalletAuthVerification(
      username: cleanUsername,
      address: cleanAddress,
      walletType: cleanWalletType,
      matrixPassword: matrixPasswordFor(
        cleanUsername,
        cleanAddress,
        walletType: cleanWalletType,
      ),
    );
  }

  String matrixPasswordFor(
    String username,
    String address, {
    String walletType = WalletAuthTypes.evm,
  }) {
    final hmac = Hmac(sha256, utf8.encode(config.secret));
    final digest = hmac.convert(
      utf8.encode(
        'xmo-wallet-v1:${normalizeWalletType(walletType)}:${normalizeUsername(username)}:${normalizeAddress(address, walletType: walletType)}',
      ),
    );
    return 'xmo_wallet_v1_${base64UrlEncode(digest.bytes)}';
  }

  static String normalizeUsername(String value) {
    final clean = value.trim();
    if (!RegExp(r'^[a-zA-Z0-9_\-]{3,32}$').hasMatch(clean)) {
      throw const WalletAuthException(
        'Username must be 3-32 characters and use only letters, numbers, _ or -',
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

  String _extractField(String message, String field) {
    final prefix = '$field: ';
    for (final line in const LineSplitter().convert(message)) {
      if (line.startsWith(prefix)) return line.substring(prefix.length).trim();
    }
    throw WalletAuthException('Missing wallet message field: $field');
  }

  void _pruneExpired() {
    final now = _now();
    _challenges.removeWhere((_, challenge) => now.isAfter(challenge.expiresAt));
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
  WalletAuthChallenge({
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
  bool used = false;

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

class WalletAuthVerification {
  const WalletAuthVerification({
    required this.username,
    required this.address,
    required this.walletType,
    required this.matrixPassword,
  });

  final String username;
  final String address;
  final String walletType;
  final String matrixPassword;

  Map<String, dynamic> toJson() => {
        'success': true,
        'username': username,
        'address': address,
        'walletType': walletType,
        'matrixPassword': matrixPassword,
      };
}

class WalletAuthException implements Exception {
  const WalletAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
