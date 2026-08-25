import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/xmo_stream_manifest.dart';
import 'package:xmo/services/matrix_media_helper.dart';
import 'package:xmo/services/streaming_playback_decision_service.dart';

void main() {
  const helper = MatrixMediaHelper(
    homeserverUrl: 'https://matrix.example.org',
    accessToken: 'access-token',
  );

  group('StreamingPlaybackDecisionService', () {
    const service = StreamingPlaybackDecisionService(mediaHelper: helper);

    test('streams public unencrypted Matrix videos directly', () {
      final decision = service.decideVideo(
        messageType: 'm.video',
        isAttachmentEncrypted: false,
        content: {
          'msgtype': 'm.video',
          'url': 'mxc://matrix.example.org/video-id',
        },
      );

      expect(decision.path, XmoStreamingPlaybackPath.directMatrixUrl);
      expect(decision.loadingLabel, 'Loading video...');
      expect(
        decision.directMediaRequest!.uri.toString(),
        'https://matrix.example.org/_matrix/client/v1/media/download/matrix.example.org/video-id',
      );
      expect(decision.directMediaRequest!.headers, {
        'Authorization': 'Bearer access-token',
      });
    });

    test('does not stream encrypted Matrix media URLs directly', () {
      final decision = service.decideVideo(
        messageType: 'm.video',
        isAttachmentEncrypted: true,
        content: {
          'msgtype': 'm.video',
          'url': 'mxc://matrix.example.org/encrypted-video',
          'file': {'url': 'mxc://matrix.example.org/encrypted-video'},
        },
      );

      expect(decision.path, XmoStreamingPlaybackPath.matrixFallback);
      expect(decision.fallbackReason, 'encrypted-without-xmo-stream');
    });

    test('uses xmo_stream for encrypted video when manifest is valid', () {
      final decision = service.decideVideo(
        messageType: 'm.video',
        isAttachmentEncrypted: true,
        content: {
          'msgtype': 'm.video',
          'file': {'url': 'mxc://matrix.example.org/fallback'},
          xmoStreamContentKey: _manifestJson(),
        },
        qualityModeName: 'original',
      );

      expect(decision.path, XmoStreamingPlaybackPath.secureXmoStream);
      expect(decision.loadingLabel, 'Preparing secure video...');
      expect(decision.manifest, isNotNull);
      expect(decision.quality, 'source');
    });

    test('falls back when xmo_stream is malformed', () {
      final decision = service.decideVideo(
        messageType: 'm.video',
        isAttachmentEncrypted: true,
        content: {
          'msgtype': 'm.video',
          xmoStreamContentKey: {..._manifestJson(), 'version': 999},
        },
      );

      expect(decision.path, XmoStreamingPlaybackPath.matrixFallback);
      expect(decision.fallbackReason, 'invalid-xmo-stream');
    });

    test('keeps files and unsupported media on Matrix fallback path', () {
      final decision = service.decideVideo(
        messageType: 'm.file',
        isAttachmentEncrypted: false,
        content: {
          'msgtype': 'm.file',
          'url': 'mxc://matrix.example.org/file-id',
        },
      );

      expect(decision.path, XmoStreamingPlaybackPath.matrixFallback);
      expect(decision.directMediaRequest, isNull);
      expect(decision.manifest, isNull);
    });

    test('can direct-stream public audio for existing audio bubbles', () {
      final request = service.directStreamRequestFor(
        messageType: 'm.audio',
        isAttachmentEncrypted: false,
        content: {
          'msgtype': 'm.audio',
          'url': 'mxc://matrix.example.org/audio-id',
        },
      );

      expect(request, isNotNull);
      expect(
        request!.uri.path,
        '/_matrix/client/v1/media/download/matrix.example.org/audio-id',
      );
    });

    test('never selects streaming paths on web', () {
      const webService = StreamingPlaybackDecisionService(
        mediaHelper: helper,
        isWeb: true,
      );

      final decision = webService.decideVideo(
        messageType: 'm.video',
        isAttachmentEncrypted: false,
        content: {
          'msgtype': 'm.video',
          'url': 'mxc://matrix.example.org/video-id',
        },
      );

      expect(decision.path, XmoStreamingPlaybackPath.matrixFallback);
      expect(
        webService.directStreamRequestFor(
          messageType: 'm.audio',
          isAttachmentEncrypted: false,
          content: {'url': 'mxc://matrix.example.org/audio-id'},
        ),
        isNull,
      );
    });
  });
}

Map<String, dynamic> _manifestJson() {
  return {
    'version': 1,
    'mime_type': 'video/mp4',
    'size': 1024,
    'chunk_size': 1024,
    'duration_ms': 1000,
    'qualities': {
      'source': {
        'chunks': [
          {
            'index': 0,
            'url': 'mxc://matrix.example.org/chunk0',
            'key': _encodedBytes(32, 1),
            'iv': _encodedBytes(16, 2),
            'sha256': _encodedBytes(32, 3),
          },
        ],
      },
    },
  };
}

String _encodedBytes(int length, int seed) {
  return base64Url.encode(List<int>.generate(length, (index) => seed + index));
}
