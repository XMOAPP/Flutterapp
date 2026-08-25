part of xmo_auth_server;

final _azureBlobUserLimiter = _AzureBlobUserRateLimiter();

Future<void> _signAzureBlobChunkUpload(HttpRequest request) async {
  if (!_azureBlobConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Azure Blob storage is not configured',
    });
    return;
  }

  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }

  final String userId;
  try {
    userId = await _userDirectoryWhoamiForRequest(request, token);
  } catch (_) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Invalid XMO session token',
    });
    return;
  }

  final body = await _readJson(request);
  final fileName = body['fileName']?.toString() ?? '';
  final contentType = body['contentType']?.toString() ?? '';
  final size = _intValue(body['size']);
  final mediaSize = _intValue(body['mediaSize']);
  final chunkIndex = _intValue(body['chunkIndex']);
  final roomId = body['roomId']?.toString().trim() ?? '';
  final cipherSha256 = body['cipherSha256']?.toString().trim() ?? '';

  if (!_azureBlobUserLimiter.allow(
        '$userId:upload-minute',
        limit: 120,
        window: const Duration(minutes: 1),
      ) ||
      !_azureBlobUserLimiter.allow(
        '$userId:upload-day',
        limit: 4096,
        window: const Duration(days: 1),
      )) {
    await _json(request, HttpStatus.tooManyRequests, {
      'success': false,
      'error': 'Azure media upload limit reached. Try again later.',
    });
    return;
  }

  if (!await _azureBlobUserJoinedRoom(
    token: token,
    userId: userId,
    roomId: roomId,
  )) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Room membership is required',
    });
    return;
  }

  try {
    final result = _azureBlobConfig.createSignedChunkUpload(
      fileName: fileName,
      contentType: contentType,
      size: size,
      mediaSize: mediaSize,
      chunkIndex: chunkIndex,
      roomId: roomId,
      ownerUserId: userId,
      cipherSha256: cipherSha256,
    );
    await _json(request, HttpStatus.ok, result.toJson());
  } on AzureBlobConfigException catch (error) {
    await _json(request, HttpStatus.badRequest, {
      'success': false,
      'error': error.message,
    });
  }
}

Future<void> _downloadAzureBlobChunk(HttpRequest request) async {
  if (!_azureBlobConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Azure Blob storage is not configured',
    });
    return;
  }
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }

  final String userId;
  try {
    userId = await _userDirectoryWhoamiForRequest(request, token);
  } catch (_) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Invalid XMO session token',
    });
    return;
  }
  if (!_azureBlobUserLimiter.allow(
    '$userId:download-minute',
    limit: 600,
    window: const Duration(minutes: 1),
  )) {
    await _json(request, HttpStatus.tooManyRequests, {
      'success': false,
      'error': 'Azure media download limit reached. Try again later.',
    });
    return;
  }

  final reference = request.uri.queryParameters['ref'] ?? '';
  final access = _azureBlobConfig.decodeAccessReference(reference);
  if (access == null) {
    await _json(request, HttpStatus.badRequest, {
      'success': false,
      'error': 'Invalid media reference',
    });
    return;
  }
  if (!await _azureBlobUserJoinedRoom(
    token: token,
    userId: userId,
    roomId: access.roomId,
  )) {
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Room membership is required',
    });
    return;
  }

  final downloadUrl = _azureBlobConfig.createSignedChunkDownload(
    blobName: access.blobName,
  );
  request.response
    ..statusCode = HttpStatus.temporaryRedirect
    ..headers.set(HttpHeaders.locationHeader, downloadUrl.toString())
    ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  await request.response.close();
}

Future<bool> _azureBlobUserJoinedRoom({
  required String token,
  required String userId,
  required String roomId,
}) async {
  if (!roomId.startsWith('!') || roomId.length > 512) return false;
  final base = Uri.parse(_azureBlobConfig.homeserverUrl);
  final uri = base.replace(
    pathSegments: [
      '_matrix',
      'client',
      'v3',
      'rooms',
      roomId,
      'state',
      'm.room.member',
      userId,
    ],
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final membershipRequest = await client.getUrl(uri);
    membershipRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $token',
    );
    final response = await membershipRequest.close().timeout(
      const Duration(seconds: 15),
    );
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    return _decodeJsonMap(body)['membership'] == 'join';
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

int _intValue(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? -1;
}

class AzureBlobConfig {
  const AzureBlobConfig({
    required this.account,
    required this.container,
    required this.accountKey,
    required this.endpoint,
    required this.publicBaseUrl,
    required this.homeserverUrl,
    required this.uploadTtl,
    required this.downloadTtl,
    required this.maxChunkBytes,
    required this.maxUploadBytes,
  });

  factory AzureBlobConfig.fromEnvironment(Map<String, String> environment) {
    final account = environment['XMO_AZURE_BLOB_ACCOUNT'] ?? '';
    final container = environment['XMO_AZURE_BLOB_CONTAINER'] ?? '';
    final endpoint =
        environment['XMO_AZURE_BLOB_ENDPOINT'] ??
        (account.isEmpty ? '' : 'https://$account.blob.core.windows.net');
    return AzureBlobConfig(
      account: account,
      container: container,
      accountKey: environment['XMO_AZURE_BLOB_ACCOUNT_KEY'] ?? '',
      endpoint: endpoint,
      publicBaseUrl:
          environment['XMO_PUBLIC_BASE_URL'] ??
          environment['XMO_WALLET_AUTH_URI'] ??
          '',
      homeserverUrl: environment['XMO_HOMESERVER_URL'] ?? 'http://synapse:8008',
      uploadTtl: Duration(
        minutes:
            int.tryParse(
              environment['XMO_AZURE_BLOB_UPLOAD_TTL_MINUTES'] ?? '',
            ) ??
            15,
      ),
      downloadTtl: Duration(
        minutes:
            int.tryParse(
              environment['XMO_AZURE_BLOB_DOWNLOAD_TTL_MINUTES'] ?? '',
            ) ??
            10,
      ),
      maxChunkBytes:
          int.tryParse(environment['XMO_AZURE_BLOB_MAX_CHUNK_BYTES'] ?? '') ??
          8 * 1024 * 1024,
      maxUploadBytes:
          int.tryParse(environment['XMO_MAX_MEDIA_UPLOAD_BYTES'] ?? '') ??
          50 * 1024 * 1024,
    );
  }

  final String account;
  final String container;
  final String accountKey;
  final String endpoint;
  final String publicBaseUrl;
  final String homeserverUrl;
  final Duration uploadTtl;
  final Duration downloadTtl;
  final int maxChunkBytes;
  final int maxUploadBytes;

  bool get isConfigured =>
      account.isNotEmpty &&
      container.isNotEmpty &&
      accountKey.isNotEmpty &&
      endpoint.isNotEmpty &&
      publicBaseUrl.startsWith('https://') &&
      homeserverUrl.isNotEmpty;

  AzureBlobSignedChunkUpload createSignedChunkUpload({
    required String fileName,
    required String contentType,
    required int size,
    required int mediaSize,
    required int chunkIndex,
    required String roomId,
    required String ownerUserId,
    required String cipherSha256,
  }) {
    if (!isConfigured) {
      throw const AzureBlobConfigException(
        'Azure Blob storage is not configured',
      );
    }
    if (size <= 0 || size > maxChunkBytes) {
      throw AzureBlobConfigException(
        'Chunk size must be between 1 and $maxChunkBytes bytes',
      );
    }
    if (mediaSize <= 0 || mediaSize > maxUploadBytes) {
      throw AzureBlobConfigException(
        'Media size must be between 1 and $maxUploadBytes bytes',
      );
    }
    if (chunkIndex < 0) {
      throw const AzureBlobConfigException('Invalid chunk index');
    }
    if (chunkIndex > 4095) {
      throw const AzureBlobConfigException('Chunk index is too large');
    }
    if (contentType != 'application/octet-stream') {
      throw const AzureBlobConfigException('Invalid encrypted chunk type');
    }
    if (!roomId.startsWith('!') || roomId.length > 512) {
      throw const AzureBlobConfigException('Invalid room ID');
    }
    if (!ownerUserId.startsWith('@') || ownerUserId.length > 512) {
      throw const AzureBlobConfigException('Invalid owner user ID');
    }
    if (!_validSha256(cipherSha256)) {
      throw const AzureBlobConfigException('Invalid encrypted chunk hash');
    }

    final blobName = _blobName(fileName: fileName, chunkIndex: chunkIndex);
    final uploadExpiresAt = DateTime.now().toUtc().add(uploadTtl);
    final baseUrl = _blobUrl(blobName);
    final uploadUrl = Uri.parse(
      '$baseUrl?${_buildSas(blobName: blobName, permissions: 'cw', expiresAt: uploadExpiresAt)}',
    );
    final accessReference = _encodeAccessReference(
      AzureBlobAccessReference(
        blobName: blobName,
        roomId: roomId,
        ownerUserId: ownerUserId,
        chunkIndex: chunkIndex,
        size: size,
        cipherSha256: cipherSha256,
      ),
    );
    final downloadUrl = Uri.parse(publicBaseUrl)
        .resolve('/auth/media/chunks/azure/download')
        .replace(queryParameters: {'ref': accessReference});

    return AzureBlobSignedChunkUpload(
      uploadUrl: uploadUrl,
      downloadUrl: downloadUrl,
      blobName: blobName,
      expiresAt: uploadExpiresAt,
    );
  }

  Uri createSignedChunkDownload({required String blobName}) {
    final expiresAt = DateTime.now().toUtc().add(downloadTtl);
    final baseUrl = _blobUrl(blobName);
    return Uri.parse(
      '$baseUrl?${_buildSas(blobName: blobName, permissions: 'r', expiresAt: expiresAt)}',
    );
  }

  AzureBlobAccessReference? decodeAccessReference(String encoded) {
    final parts = encoded.split('.');
    if (parts.length != 2 || parts.any((part) => part.isEmpty)) return null;
    try {
      final payload = _decodeBase64Url(parts[0]);
      final suppliedSignature = _decodeBase64Url(parts[1]);
      final expectedSignature = Hmac(
        sha256,
        base64Decode(accountKey),
      ).convert(payload).bytes;
      if (!_constantTimeEquals(suppliedSignature, expectedSignature)) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) return null;
      return AzureBlobAccessReference.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return null;
    }
  }

  String _encodeAccessReference(AzureBlobAccessReference access) {
    final payload = utf8.encode(jsonEncode(access.toJson()));
    final signature = Hmac(
      sha256,
      base64Decode(accountKey),
    ).convert(payload).bytes;
    return '${base64Url.encode(payload).replaceAll('=', '')}.'
        '${base64Url.encode(signature).replaceAll('=', '')}';
  }

  String _blobName({required String fileName, required int chunkIndex}) {
    final cleaned = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final safeName = cleaned.isEmpty ? 'media' : cleaned;
    final nonce = _randomToken(18);
    final now = DateTime.now().toUtc();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    return '$year/$month/$nonce-$chunkIndex-$safeName';
  }

  String _blobUrl(String blobName) {
    final cleanEndpoint = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    return '$cleanEndpoint/$container/${Uri.encodeComponent(blobName).replaceAll('%2F', '/')}';
  }

  String _buildSas({
    required String blobName,
    required String permissions,
    required DateTime expiresAt,
  }) {
    const version = '2023-11-03';
    final start = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5))
        .toIso8601String()
        .replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    final expiry = expiresAt.toIso8601String().replaceFirst(
      RegExp(r'\.\d+Z$'),
      'Z',
    );
    final canonicalizedResource = '/blob/$account/$container/$blobName';
    final stringToSign = [
      permissions,
      start,
      expiry,
      canonicalizedResource,
      '',
      '',
      'https',
      version,
      'b',
      '',
      '',
      '',
      '',
      '',
      '',
    ].join('\n');

    final keyBytes = base64Decode(accountKey);
    final signature = Hmac(
      sha256,
      keyBytes,
    ).convert(utf8.encode(stringToSign)).bytes;
    final params = <String, String>{
      'sv': version,
      'spr': 'https',
      'st': start,
      'se': expiry,
      'sr': 'b',
      'sp': permissions,
      'sig': base64Encode(signature),
    };
    return params.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }
}

String _randomToken(int length) {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(
    length,
    (_) => alphabet[_random.nextInt(alphabet.length)],
  ).join();
}

class AzureBlobSignedChunkUpload {
  const AzureBlobSignedChunkUpload({
    required this.uploadUrl,
    required this.downloadUrl,
    required this.blobName,
    required this.expiresAt,
  });

  final Uri uploadUrl;
  final Uri downloadUrl;
  final String blobName;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'success': true,
    'uploadUrl': uploadUrl.toString(),
    'downloadUrl': downloadUrl.toString(),
    'blobName': blobName,
    'expiresAt': expiresAt.toIso8601String(),
  };
}

class AzureBlobAccessReference {
  const AzureBlobAccessReference({
    required this.blobName,
    required this.roomId,
    required this.ownerUserId,
    required this.chunkIndex,
    required this.size,
    required this.cipherSha256,
  });

  factory AzureBlobAccessReference.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1 ||
        json['blob'] is! String ||
        json['room'] is! String ||
        json['owner'] is! String ||
        json['index'] is! int ||
        json['size'] is! int ||
        json['sha256'] is! String) {
      throw const FormatException('Invalid Azure media reference');
    }
    final reference = AzureBlobAccessReference(
      blobName: json['blob'] as String,
      roomId: json['room'] as String,
      ownerUserId: json['owner'] as String,
      chunkIndex: json['index'] as int,
      size: json['size'] as int,
      cipherSha256: json['sha256'] as String,
    );
    if (!RegExp(
          r'^\d{4}/\d{2}/[A-Za-z0-9._-]+$',
        ).hasMatch(reference.blobName) ||
        !reference.roomId.startsWith('!') ||
        reference.roomId.length > 512 ||
        !reference.ownerUserId.startsWith('@') ||
        reference.ownerUserId.length > 512 ||
        reference.chunkIndex < 0 ||
        reference.chunkIndex > 4095 ||
        reference.size <= 0 ||
        !_validSha256(reference.cipherSha256)) {
      throw const FormatException('Invalid Azure media reference values');
    }
    return reference;
  }

  final String blobName;
  final String roomId;
  final String ownerUserId;
  final int chunkIndex;
  final int size;
  final String cipherSha256;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'blob': blobName,
    'room': roomId,
    'owner': ownerUserId,
    'index': chunkIndex,
    'size': size,
    'sha256': cipherSha256,
  };
}

class _AzureBlobUserRateLimiter {
  final Map<String, List<DateTime>> _requests = {};

  bool allow(String key, {required int limit, required Duration window}) {
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(window);
    final entries = _requests.putIfAbsent(key, () => <DateTime>[])
      ..removeWhere((timestamp) => timestamp.isBefore(cutoff));
    if (entries.length >= limit) return false;
    entries.add(now);
    if (_requests.length > 10000) {
      _requests.removeWhere(
        (_, timestamps) =>
            timestamps.isEmpty || timestamps.last.isBefore(cutoff),
      );
    }
    return true;
  }
}

bool _validSha256(String value) {
  try {
    return _decodeBase64Url(value).length == 32;
  } catch (_) {
    return false;
  }
}

List<int> _decodeBase64Url(String value) {
  if (value.isEmpty || value.length > 128) {
    throw const FormatException('Invalid base64url value');
  }
  final padding = (4 - value.length % 4) % 4;
  final suffix = List.filled(padding, '=').join();
  return base64Url.decode('$value$suffix');
}

bool _constantTimeEquals(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var i = 0; i < first.length; i++) {
    difference |= first[i] ^ second[i];
  }
  return difference == 0;
}

class AzureBlobConfigException implements Exception {
  const AzureBlobConfigException(this.message);

  final String message;
}
