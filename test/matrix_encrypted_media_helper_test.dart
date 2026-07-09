import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/matrix_encrypted_media_helper.dart';

class _DeterministicRandom implements Random {
  _DeterministicRandom(this._bytes);

  final List<int> _bytes;
  int _index = 0;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);

  @override
  int nextInt(int max) {
    final value = _bytes[_index % _bytes.length];
    _index += 1;
    return value % max;
  }
}

void main() {
  group('MatrixEncryptedMediaHelper', () {
    test('encrypts Matrix media without native libcrypto', () async {
      final helper = MatrixEncryptedMediaHelper(
        random: _DeterministicRandom(List<int>.generate(48, (i) => i + 1)),
      );
      final clearText = Uint8List.fromList(utf8.encode('voice message bytes'));

      final encryptedFile = await helper.encrypt(clearText);

      expect(encryptedFile.data, isNot(clearText));
      expect(
          base64Url.decode(base64.normalize(encryptedFile.k)), hasLength(32));
      expect(base64.decode(base64.normalize(encryptedFile.iv)), hasLength(16));
      expect(
        base64.encode(dart_crypto.sha256.convert(encryptedFile.data).bytes),
        base64.normalize(encryptedFile.sha256),
      );
    });

    test('decrypts its own encrypted payload', () async {
      final helper = MatrixEncryptedMediaHelper(
        random: _DeterministicRandom(List<int>.generate(48, (i) => 255 - i)),
      );
      final clearText = Uint8List.fromList(List<int>.generate(64, (i) => i));

      final encryptedFile = await helper.encrypt(clearText);
      final decrypted = await helper.decrypt(encryptedFile);

      expect(decrypted, clearText);
    });
  });
}
