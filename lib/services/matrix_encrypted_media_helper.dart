import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:matrix/matrix.dart';

class MatrixEncryptedMediaHelper {
  const MatrixEncryptedMediaHelper({Random? random}) : _random = random;

  final Random? _random;

  static const int _keyLength = 32;
  static const int _ivLength = 16;

  Future<EncryptedFile> encrypt(Uint8List bytes) async {
    final key = _secureRandomBytes(_keyLength);
    final iv = _secureRandomBytes(_ivLength);
    final cipherText = await _aesCtr(bytes, key: key, iv: iv);
    final sha256 = dart_crypto.sha256.convert(cipherText).bytes;

    return EncryptedFile(
      data: Uint8List.fromList(cipherText),
      k: base64Url.encode(key).replaceAll('=', ''),
      iv: base64.encode(iv).replaceAll('=', ''),
      sha256: base64.encode(sha256).replaceAll('=', ''),
    );
  }

  Future<Uint8List?> decrypt(EncryptedFile file) async {
    final expectedHash = base64.normalize(file.sha256);
    final actualHash =
        base64.encode(dart_crypto.sha256.convert(file.data).bytes);
    if (actualHash != expectedHash) {
      return null;
    }

    final key = _base64DecodeUnpadded(base64.normalize(file.k));
    final iv = _base64DecodeUnpadded(base64.normalize(file.iv));
    final clearText = await _aesCtr(file.data, key: key, iv: iv);
    return Uint8List.fromList(clearText);
  }

  Uint8List _secureRandomBytes(int length) {
    final random = _random ?? Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Future<List<int>> _aesCtr(
    List<int> input, {
    required List<int> key,
    required List<int> iv,
  }) async {
    const algorithm = DartAesCtr.with256bits(
      macAlgorithm: MacAlgorithm.empty,
    );
    final secretBox = await algorithm.encrypt(
      input,
      secretKey: SecretKeyData(key),
      nonce: iv,
    );
    return secretBox.cipherText;
  }

  static Uint8List _base64DecodeUnpadded(String value) {
    final needEquals = (4 - (value.length % 4)) % 4;
    return base64.decode(value + ('=' * needEquals));
  }
}
