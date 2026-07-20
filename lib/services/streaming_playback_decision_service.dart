import '../config/app_config.dart';
import '../models/xmo_stream_manifest.dart';
import 'matrix_media_helper.dart';

enum XmoStreamingPlaybackPath {
  directMatrixUrl,
  secureXmoStream,
  matrixFallback,
}

class XmoStreamingPlaybackDecision {
  const XmoStreamingPlaybackDecision._({
    required this.path,
    required this.loadingLabel,
    this.directMediaRequest,
    this.manifest,
    this.quality,
    this.fallbackReason,
  });

  factory XmoStreamingPlaybackDecision.directMatrixUrl(
    MatrixMediaRequest request,
  ) {
    return XmoStreamingPlaybackDecision._(
      path: XmoStreamingPlaybackPath.directMatrixUrl,
      loadingLabel: 'Loading video...',
      directMediaRequest: request,
    );
  }

  factory XmoStreamingPlaybackDecision.secureXmoStream({
    required XmoStreamManifest manifest,
    required String quality,
  }) {
    return XmoStreamingPlaybackDecision._(
      path: XmoStreamingPlaybackPath.secureXmoStream,
      loadingLabel: 'Preparing secure video...',
      manifest: manifest,
      quality: quality,
    );
  }

  factory XmoStreamingPlaybackDecision.matrixFallback([String? reason]) {
    return XmoStreamingPlaybackDecision._(
      path: XmoStreamingPlaybackPath.matrixFallback,
      loadingLabel: 'Opening...',
      fallbackReason: reason,
    );
  }

  final XmoStreamingPlaybackPath path;
  final String loadingLabel;
  final MatrixMediaRequest? directMediaRequest;
  final XmoStreamManifest? manifest;
  final String? quality;
  final String? fallbackReason;
}

class StreamingPlaybackDecisionService {
  const StreamingPlaybackDecisionService({
    required MatrixMediaHelper mediaHelper,
    bool isWeb = false,
  })  : _mediaHelper = mediaHelper,
        _isWeb = isWeb;

  final MatrixMediaHelper _mediaHelper;
  final bool _isWeb;

  XmoStreamingPlaybackDecision decideVideo({
    required String messageType,
    required bool isAttachmentEncrypted,
    required Map<dynamic, dynamic> content,
    String qualityModeName = AppConfig.streamQualityMode,
  }) {
    if (_isWeb) {
      return XmoStreamingPlaybackDecision.matrixFallback('web');
    }
    if (messageType != 'm.video') {
      return XmoStreamingPlaybackDecision.matrixFallback('not-video');
    }

    final directRequest = directStreamRequestFor(
      messageType: messageType,
      isAttachmentEncrypted: isAttachmentEncrypted,
      content: content,
    );
    if (directRequest != null) {
      return XmoStreamingPlaybackDecision.directMatrixUrl(directRequest);
    }

    if (!isAttachmentEncrypted) {
      return XmoStreamingPlaybackDecision.matrixFallback(
        'unencrypted-without-direct-url',
      );
    }

    try {
      final manifest = XmoStreamManifest.fromEventContent(content);
      if (manifest == null) {
        return XmoStreamingPlaybackDecision.matrixFallback(
          'encrypted-without-xmo-stream',
        );
      }
      final quality = manifest.resolveQuality(
        XmoStreamQualityMode.fromName(qualityModeName),
      );
      return XmoStreamingPlaybackDecision.secureXmoStream(
        manifest: manifest,
        quality: quality,
      );
    } catch (e) {
      return XmoStreamingPlaybackDecision.matrixFallback(
        'invalid-xmo-stream',
      );
    }
  }

  MatrixMediaRequest? directStreamRequestFor({
    required String messageType,
    required bool isAttachmentEncrypted,
    required Map<dynamic, dynamic> content,
  }) {
    if (_isWeb) return null;
    if (messageType != 'm.video' && messageType != 'm.audio') return null;
    if (isAttachmentEncrypted) return null;

    final rawUrl = content['url'];
    if (rawUrl is! String || rawUrl.trim().isEmpty) return null;
    final url = rawUrl.trim();
    if (url.startsWith('mxc://')) {
      return _mediaHelper.fromMxc(url);
    }

    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('https') && !uri.isScheme('http'))) {
      return null;
    }
    return _mediaHelper.fromUrl(uri);
  }
}
