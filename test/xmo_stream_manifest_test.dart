import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/xmo_stream_manifest.dart';

void main() {
  group('XmoStreamManifest', () {
    test('parses a valid stream manifest from event content', () {
      final manifest = XmoStreamManifest.fromEventContent({
        'msgtype': 'm.video',
        xmoStreamContentKey: _manifestJson(),
      });

      expect(manifest, isNotNull);
      expect(manifest!.version, 1);
      expect(manifest.mimeType, 'video/mp4');
      expect(manifest.size, 4194304);
      expect(manifest.chunkSize, 2097152);
      expect(manifest.durationMs, 65000);
      expect(manifest.sourceQuality, isNotNull);
      expect(manifest.sourceQuality!.chunks, hasLength(2));
      expect(manifest.resolveQuality(XmoStreamQualityMode.auto), 'source');
      expect(manifest.sourceQuality!.chunks.first.index, 0);
      expect(manifest.sourceQuality!.chunks.first.url, 'mxc://server/chunk0');
      expect(manifest.sourceQuality!.chunks.first.key, _encodedKey(0));
      expect(manifest.sourceQuality!.chunks.first.iv, _encodedIv(0));
      expect(manifest.sourceQuality!.chunks.first.sha256, _encodedHash(0));
    });

    test('returns null when event content has no xmo_stream', () {
      expect(
        XmoStreamManifest.fromEventContent({
          'msgtype': 'm.video',
          'body': 'video.mp4',
        }),
        isNull,
      );
    });

    test('round-trips through json', () {
      final manifest = XmoStreamManifest.fromJson(_manifestJson());
      final decoded = XmoStreamManifest.fromJson(manifest.toJson());

      expect(decoded.toJson(), manifest.toJson());
    });

    test('parses quality metadata and resolves playback modes', () {
      final json = _manifestJson();
      json['qualities'] = Map<String, dynamic>.from(
        json['qualities'] as Map<dynamic, dynamic>,
      );
      (json['qualities'] as Map)['480p'] = {
        'size': 2048,
        'chunk_size': 1024,
        'mime_type': 'video/mp4',
        'chunks': [
          {
            'index': 0,
            'url': 'mxc://server/480p0',
            'key': _encodedKey(10),
            'iv': _encodedIv(10),
            'sha256': _encodedHash(10),
          },
          {
            'index': 1,
            'url': 'mxc://server/480p1',
            'key': _encodedKey(11),
            'iv': _encodedIv(11),
            'sha256': _encodedHash(11),
          },
        ],
      };
      (json['qualities'] as Map)['240p'] = {
        'size': 1024,
        'chunk_size': 1024,
        'chunks': [
          {
            'index': 0,
            'url': 'mxc://server/240p0',
            'key': _encodedKey(20),
            'iv': _encodedIv(20),
            'sha256': _encodedHash(20),
          },
        ],
      };

      final manifest = XmoStreamManifest.fromJson(json);

      expect(manifest.quality('480p')!.size, 2048);
      expect(manifest.quality('480p')!.chunkSize, 1024);
      expect(manifest.quality('480p')!.mimeType, 'video/mp4');
      expect(manifest.resolveQuality(XmoStreamQualityMode.auto), '480p');
      expect(manifest.resolveQuality(XmoStreamQualityMode.dataSaver), '240p');
      expect(manifest.resolveQuality(XmoStreamQualityMode.highQuality), '480p');
      expect(manifest.resolveQuality(XmoStreamQualityMode.original), 'source');
    });

    test('rejects missing required top-level fields', () {
      final json = _manifestJson()..remove('mime_type');

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects non-positive size and chunk size', () {
      expect(
        () => XmoStreamManifest.fromJson(_manifestJson()..['size'] = 0),
        throwsA(isA<XmoStreamManifestException>()),
      );
      expect(
        () => XmoStreamManifest.fromJson(_manifestJson()..['chunk_size'] = -1),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects unsupported versions', () {
      expect(
        () => XmoStreamManifest.fromJson(_manifestJson()..['version'] = 2),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects duplicate chunk indexes', () {
      final json = _manifestJson();
      final chunks =
          (json['qualities'] as Map)['source']['chunks'] as List<dynamic>;
      (chunks[1] as Map)['index'] = 0;

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects non-contiguous chunk indexes', () {
      final json = _manifestJson();
      final chunks =
          (json['qualities'] as Map)['source']['chunks'] as List<dynamic>;
      (chunks[1] as Map)['index'] = 2;

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects missing chunk crypto fields', () {
      final json = _manifestJson();
      final chunks =
          (json['qualities'] as Map)['source']['chunks'] as List<dynamic>;
      (chunks[0] as Map).remove('key');

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects invalid chunk urls', () {
      final json = _manifestJson();
      final chunks =
          (json['qualities'] as Map)['source']['chunks'] as List<dynamic>;
      (chunks[0] as Map)['url'] = 'file:///tmp/chunk0';

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects insecure http chunk urls', () {
      final json = _manifestJson();
      final chunks =
          (json['qualities'] as Map)['source']['chunks'] as List<dynamic>;
      (chunks[0] as Map)['url'] = 'http://example.org/chunk0';

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects malformed crypto values', () {
      final json = _manifestJson();
      final chunks =
          (json['qualities'] as Map)['source']['chunks'] as List<dynamic>;
      (chunks[0] as Map)['sha256'] = 'not-a-valid-sha256';

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects reused key and iv pairs', () {
      final json = _manifestJson();
      final chunks =
          (json['qualities'] as Map)['source']['chunks'] as List<dynamic>;
      (chunks[1] as Map)['key'] = (chunks[0] as Map)['key'];
      (chunks[1] as Map)['iv'] = (chunks[0] as Map)['iv'];

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });

    test('rejects chunk count that does not match declared size', () {
      final json = _manifestJson()..['size'] = 4194305;

      expect(
        () => XmoStreamManifest.fromJson(json),
        throwsA(isA<XmoStreamManifestException>()),
      );
    });
  });
}

Map<String, dynamic> _manifestJson() {
  return {
    'version': 1,
    'mime_type': 'video/mp4',
    'size': 4194304,
    'chunk_size': 2097152,
    'duration_ms': 65000,
    'qualities': {
      'source': {
        'chunks': [
          {
            'index': 0,
            'url': 'mxc://server/chunk0',
            'key': _encodedKey(0),
            'iv': _encodedIv(0),
            'sha256': _encodedHash(0),
          },
          {
            'index': 1,
            'url': 'mxc://server/chunk1',
            'key': _encodedKey(1),
            'iv': _encodedIv(1),
            'sha256': _encodedHash(1),
          },
        ],
      },
    },
  };
}

String _encodedKey(int seed) => _encodedBytes(32, seed, urlSafe: true);

String _encodedIv(int seed) => _encodedBytes(16, seed);

String _encodedHash(int seed) => _encodedBytes(32, seed);

String _encodedBytes(int length, int seed, {bool urlSafe = false}) {
  final bytes = List<int>.generate(length, (index) => (seed + index) % 256);
  final encoded = urlSafe ? base64Url.encode(bytes) : base64.encode(bytes);
  return encoded.replaceAll('=', '');
}
