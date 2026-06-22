/// A token-safe Matrix media request.
///
/// Matrix media URLs are safe to pass to image and video widgets. Credentials
/// are supplied only through [headers], never in the URL query string.
class MatrixMediaRequest {
  final Uri uri;
  final Map<String, String> headers;

  const MatrixMediaRequest({
    required this.uri,
    this.headers = const <String, String>{},
  });
}

/// Builds Matrix media requests for rendering and downloading attachments.
class MatrixMediaHelper {
  final String homeserverUrl;
  final String? accessToken;

  const MatrixMediaHelper({
    required this.homeserverUrl,
    required this.accessToken,
  });

  MatrixMediaRequest? fromMxc(
    String? mxcUrl, {
    int? width,
    int? height,
  }) {
    if (mxcUrl == null || !mxcUrl.startsWith('mxc://')) return null;

    final mxc = Uri.tryParse(mxcUrl);
    if (mxc == null || mxc.authority.isEmpty || mxc.pathSegments.isEmpty) {
      return null;
    }

    final isThumbnail = width != null && height != null;
    final pathSegments = <String>[
      '_matrix',
      'client',
      'v1',
      'media',
      isThumbnail ? 'thumbnail' : 'download',
      mxc.authority,
      ...mxc.pathSegments,
    ];
    final base = Uri.parse(homeserverUrl);
    final uri = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: pathSegments,
      queryParameters: isThumbnail
          ? <String, String>{
              'width': width.toString(),
              'height': height.toString(),
              'method': 'scale',
            }
          : null,
    );

    return MatrixMediaRequest(uri: uri, headers: _authorizationHeaders());
  }

  /// Normalizes SDK-provided legacy media URLs and returns safe headers.
  MatrixMediaRequest fromUrl(Uri url) {
    final query = Map<String, String>.from(url.queryParameters)
      ..remove('access_token');
    var normalized = url.replace(queryParameters: query);
    if (url.path.startsWith('/_matrix/media/v3/')) {
      normalized = url.replace(
        path: url.path.replaceFirst(
          '/_matrix/media/v3/',
          '/_matrix/client/v1/media/',
        ),
      );
    }

    final isMatrixMedia = normalized.path.startsWith('/_matrix/client/') &&
        normalized.path.contains('/media/');
    return MatrixMediaRequest(
      uri: normalized,
      headers:
          isMatrixMedia ? _authorizationHeaders() : const <String, String>{},
    );
  }

  Map<String, String> _authorizationHeaders() {
    final token = accessToken;
    if (token == null || token.isEmpty) return const <String, String>{};
    return <String, String>{'Authorization': 'Bearer $token'};
  }
}
