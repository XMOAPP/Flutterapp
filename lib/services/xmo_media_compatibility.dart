import '../models/xmo_stream_manifest.dart';

export '../models/xmo_stream_manifest.dart'
    show XmoStreamManifest, xmoStreamContentKey;

class XmoMediaCompatibility {
  const XmoMediaCompatibility._();

  static Map<String, dynamic> withOptionalStream({
    required Map<String, dynamic> matrixContent,
    Map<String, dynamic>? xmoStream,
  }) {
    final content = Map<String, dynamic>.from(matrixContent);
    if (xmoStream == null || xmoStream.isEmpty) return content;

    content[xmoStreamContentKey] = Map<String, dynamic>.from(xmoStream);
    return content;
  }

  static bool hasMatrixMediaFallback(Map<String, dynamic> content) {
    final hasBasicFields =
        content['msgtype'] is String &&
        content['body'] is String &&
        content['info'] is Map;
    if (!hasBasicFields) return false;

    return content['url'] is String || content['file'] is Map;
  }

  static XmoStreamManifest? streamManifestFromContent(
    Map<dynamic, dynamic> content,
  ) {
    return XmoStreamManifest.fromEventContent(content);
  }
}
