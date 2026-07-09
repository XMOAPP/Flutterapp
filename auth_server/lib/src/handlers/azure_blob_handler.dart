part of xmo_auth_server;

Future<void> _signAzureBlobChunkUpload(HttpRequest request) async {
  if (!_azureBlobConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Azure Blob storage is not configured',
    });
    return;
  }

  final body = await _readJson(request);
  final fileName = body['fileName']?.toString() ?? '';
  final contentType = body['contentType']?.toString() ?? '';
  final size = _intValue(body['size']);
  final chunkIndex = _intValue(body['chunkIndex']);

  try {
    final result = _azureBlobConfig.createSignedChunkUpload(
      fileName: fileName,
      contentType: contentType,
      size: size,
      chunkIndex: chunkIndex,
    );
    await _json(request, HttpStatus.ok, result.toJson());
  } on AzureBlobConfigException catch (error) {
    await _json(request, HttpStatus.badRequest, {
      'success': false,
      'error': error.message,
    });
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
    required this.uploadTtl,
    required this.downloadTtl,
    required this.maxChunkBytes,
  });

  factory AzureBlobConfig.fromEnvironment(Map<String, String> environment) {
    final account = environment['XMO_AZURE_BLOB_ACCOUNT'] ?? '';
    final container = environment['XMO_AZURE_BLOB_CONTAINER'] ?? '';
    final endpoint = environment['XMO_AZURE_BLOB_ENDPOINT'] ??
        (account.isEmpty ? '' : 'https://$account.blob.core.windows.net');
    return AzureBlobConfig(
      account: account,
      container: container,
      accountKey: environment['XMO_AZURE_BLOB_ACCOUNT_KEY'] ?? '',
      endpoint: endpoint,
      uploadTtl: Duration(
        minutes: int.tryParse(
              environment['XMO_AZURE_BLOB_UPLOAD_TTL_MINUTES'] ?? '',
            ) ??
            15,
      ),
      downloadTtl: Duration(
        days: int.tryParse(
              environment['XMO_AZURE_BLOB_DOWNLOAD_TTL_DAYS'] ?? '',
            ) ??
            30,
      ),
      maxChunkBytes: int.tryParse(
            environment['XMO_AZURE_BLOB_MAX_CHUNK_BYTES'] ?? '',
          ) ??
          8 * 1024 * 1024,
    );
  }

  final String account;
  final String container;
  final String accountKey;
  final String endpoint;
  final Duration uploadTtl;
  final Duration downloadTtl;
  final int maxChunkBytes;

  bool get isConfigured =>
      account.isNotEmpty &&
      container.isNotEmpty &&
      accountKey.isNotEmpty &&
      endpoint.isNotEmpty;

  AzureBlobSignedChunkUpload createSignedChunkUpload({
    required String fileName,
    required String contentType,
    required int size,
    required int chunkIndex,
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
    if (chunkIndex < 0) {
      throw const AzureBlobConfigException('Invalid chunk index');
    }

    final blobName = _blobName(fileName: fileName, chunkIndex: chunkIndex);
    final uploadExpiresAt = DateTime.now().toUtc().add(uploadTtl);
    final downloadExpiresAt = DateTime.now().toUtc().add(downloadTtl);
    final baseUrl = _blobUrl(blobName);
    final uploadUrl = Uri.parse(
      '$baseUrl?${_buildSas(blobName: blobName, permissions: 'cw', expiresAt: uploadExpiresAt)}',
    );
    final downloadUrl = Uri.parse(
      '$baseUrl?${_buildSas(blobName: blobName, permissions: 'r', expiresAt: downloadExpiresAt)}',
    );

    return AzureBlobSignedChunkUpload(
      uploadUrl: uploadUrl,
      downloadUrl: downloadUrl,
      blobName: blobName,
      expiresAt: downloadExpiresAt,
    );
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
    final expiry =
        expiresAt.toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
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
    final signature =
        Hmac(sha256, keyBytes).convert(utf8.encode(stringToSign)).bytes;
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
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
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

class AzureBlobConfigException implements Exception {
  const AzureBlobConfigException(this.message);

  final String message;
}
