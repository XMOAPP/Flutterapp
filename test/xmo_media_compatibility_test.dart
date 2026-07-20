import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/xmo_media_compatibility.dart';

void main() {
  group('XmoMediaCompatibility', () {
    test('keeps normal Matrix media fields without XMO stream metadata', () {
      final content = XmoMediaCompatibility.withOptionalStream(
        matrixContent: {
          'msgtype': 'm.video',
          'body': 'video.mp4',
          'url': 'mxc://server/media',
          'info': {
            'mimetype': 'video/mp4',
            'size': 42,
          },
        },
      );

      expect(content['msgtype'], 'm.video');
      expect(content['body'], 'video.mp4');
      expect(content['url'], 'mxc://server/media');
      expect(content['info'], isA<Map>());
      expect(content.containsKey(xmoStreamContentKey), isFalse);
      expect(XmoMediaCompatibility.hasMatrixMediaFallback(content), isTrue);
    });

    test('adds xmo_stream beside normal Matrix media fallback', () {
      final content = XmoMediaCompatibility.withOptionalStream(
        matrixContent: {
          'msgtype': 'm.video',
          'body': 'video.mp4',
          'url': 'mxc://server/fallback',
          'info': {
            'mimetype': 'video/mp4',
            'size': 104857600,
          },
        },
        xmoStream: _validManifest(),
      );

      expect(content['url'], 'mxc://server/fallback');
      expect(content[xmoStreamContentKey], isA<Map<String, dynamic>>());
      expect(
        XmoMediaCompatibility.streamManifestFromContent(content)?.mimeType,
        'video/mp4',
      );
      expect(XmoMediaCompatibility.hasMatrixMediaFallback(content), isTrue);
    });

    test('accepts encrypted Matrix file fallback beside xmo_stream', () {
      final content = XmoMediaCompatibility.withOptionalStream(
        matrixContent: {
          'msgtype': 'm.video',
          'body': 'video.mp4',
          'file': {
            'url': 'mxc://server/encrypted',
            'v': 'v2',
          },
          'info': {
            'mimetype': 'video/mp4',
            'size': 104857600,
          },
        },
        xmoStream: {'version': 1},
      );

      expect(content['file'], isA<Map>());
      expect(content[xmoStreamContentKey], {'version': 1});
      expect(XmoMediaCompatibility.hasMatrixMediaFallback(content), isTrue);
    });

    test('does not treat xmo_stream alone as Matrix media fallback', () {
      final content = {
        'msgtype': 'm.video',
        'body': 'video.mp4',
        'info': {
          'mimetype': 'video/mp4',
          'size': 104857600,
        },
        xmoStreamContentKey: _validManifest(),
      };

      expect(XmoMediaCompatibility.hasMatrixMediaFallback(content), isFalse);
      expect(
        XmoMediaCompatibility.streamManifestFromContent(content),
        isNotNull,
      );
    });
  });
}

Map<String, dynamic> _validManifest() {
  return {
    'version': 1,
    'mime_type': 'video/mp4',
    'size': 2097152,
    'chunk_size': 2097152,
    'duration_ms': 65000,
    'qualities': {
      'source': {
        'chunks': [
          {
            'index': 0,
            'url': 'mxc://server/chunk0',
            'key': _encodedBytes(32, 0, urlSafe: true),
            'iv': _encodedBytes(16, 1),
            'sha256': _encodedBytes(32, 2),
          },
        ],
      },
    },
  };
}

String _encodedBytes(int length, int seed, {bool urlSafe = false}) {
  final bytes = List<int>.generate(length, (index) => (seed + index) % 256);
  final encoded = urlSafe ? base64Url.encode(bytes) : base64.encode(bytes);
  return encoded.replaceAll('=', '');
}
