import 'dart:convert';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/request_body.dart';

void main() {
  group('readBoundedJsonObject', () {
    test('reads a JSON object split across chunks', () async {
      final result = await readBoundedJsonObject(
        Stream.fromIterable(<List<int>>[
          utf8.encode('{"email":"alice@'),
          utf8.encode('example.com"}'),
        ]),
      );

      expect(result, <String, dynamic>{'email': 'alice@example.com'});
    });

    test('allows a body exactly at the configured limit', () async {
      final body = utf8.encode('{"ok":true}');

      final result = await readBoundedJsonObject(
        Stream<List<int>>.fromIterable(<List<int>>[body]),
        maxBytes: body.length,
      );

      expect(result, <String, dynamic>{'ok': true});
    });

    test('rejects an oversized chunked body with no declared length', () async {
      await expectLater(
        readBoundedJsonObject(
          Stream<List<int>>.fromIterable(<List<int>>[
            List<int>.filled(4, 0x61),
            <int>[0x62],
          ]),
          maxBytes: 4,
        ),
        throwsA(isA<RequestBodyTooLargeException>()),
      );
    });

    test(
      'rejects an oversized declared length before consuming the body',
      () async {
        var consumed = false;
        final body = Stream<List<int>>.multi((controller) {
          consumed = true;
          controller.add(utf8.encode('{}'));
          controller.close();
        });

        await expectLater(
          readBoundedJsonObject(body, declaredContentLength: 5, maxBytes: 4),
          throwsA(isA<RequestBodyTooLargeException>()),
        );
        expect(consumed, isFalse);
      },
    );

    test('rejects invalid JSON and non-object JSON', () async {
      await expectLater(
        readBoundedJsonObject(Stream.value(utf8.encode('{'))),
        throwsA(isA<JsonRequestBodyException>()),
      );
      await expectLater(
        readBoundedJsonObject(Stream.value(utf8.encode('[]'))),
        throwsA(isA<JsonRequestBodyException>()),
      );
    });
  });
}
