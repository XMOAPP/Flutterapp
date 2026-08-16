import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../config/media_upload_policy.dart';

class AzureBlobChunkSignRequest {
  const AzureBlobChunkSignRequest({
    required this.fileName,
    required this.contentType,
    required this.size,
    required this.chunkIndex,
    required this.mediaSize,
    required this.roomId,
    required this.cipherSha256,
  });

  final String fileName;
  final String contentType;
  final int size;
  final int chunkIndex;
  final int mediaSize;
  final String roomId;
  final String cipherSha256;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'contentType': contentType,
    'size': size,
    'chunkIndex': chunkIndex,
    'mediaSize': mediaSize,
    'roomId': roomId,
    'cipherSha256': cipherSha256,
  };
}

class AzureBlobChunkUploadTarget {
  const AzureBlobChunkUploadTarget({
    required this.uploadUrl,
    required this.downloadUrl,
    this.blobName,
    this.expiresAt,
  });

  final Uri uploadUrl;
  final Uri downloadUrl;
  final String? blobName;
  final DateTime? expiresAt;

  factory AzureBlobChunkUploadTarget.fromJson(Map<String, dynamic> json) {
    final uploadUrl = json['uploadUrl']?.toString();
    final downloadUrl = json['downloadUrl']?.toString();
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const FormatException('Missing Azure upload URL');
    }
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw const FormatException('Missing Azure download URL');
    }
    return AzureBlobChunkUploadTarget(
      uploadUrl: Uri.parse(uploadUrl),
      downloadUrl: Uri.parse(downloadUrl),
      blobName: json['blobName']?.toString(),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
    );
  }
}

typedef AzureBlobChunkSigner =
    Future<AzureBlobChunkUploadTarget> Function(
      AzureBlobChunkSignRequest request,
    );

typedef AzureBlobChunkUploader =
    Future<void> Function({
      required Uri uploadUrl,
      required Uint8List encryptedBytes,
      required String contentType,
    });

typedef AzureBlobAccessTokenProvider = String? Function();

class AzureBlobChunkStorageService {
  AzureBlobChunkStorageService({
    required this.signingEndpoint,
    AzureBlobChunkSigner? signer,
    AzureBlobChunkUploader? uploader,
    AzureBlobAccessTokenProvider? accessTokenProvider,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _signer = signer,
       _uploader = uploader,
       _accessTokenProvider = accessTokenProvider,
       _httpClient = httpClient ?? HttpClient();

  final Uri signingEndpoint;
  final AzureBlobChunkSigner? _signer;
  final AzureBlobChunkUploader? _uploader;
  final AzureBlobAccessTokenProvider? _accessTokenProvider;
  final HttpClient _httpClient;
  final Duration timeout;

  void close() => _httpClient.close(force: true);

  Future<Uri> uploadEncryptedChunk({
    required Uint8List encryptedBytes,
    required String fileName,
    required String contentType,
    required int chunkIndex,
    required int mediaSize,
    required String roomId,
  }) async {
    MediaUploadPolicy.validate(mediaSize);
    final request = AzureBlobChunkSignRequest(
      fileName: fileName,
      contentType: contentType,
      size: encryptedBytes.length,
      chunkIndex: chunkIndex,
      mediaSize: mediaSize,
      roomId: roomId,
      cipherSha256: base64UrlEncode(
        sha256.convert(encryptedBytes).bytes,
      ).replaceAll('=', ''),
    );
    final target = await (_signer ?? _signUpload)(request);
    await (_uploader ?? _putBlob)(
      uploadUrl: target.uploadUrl,
      encryptedBytes: encryptedBytes,
      contentType: contentType,
    );
    return target.downloadUrl;
  }

  Future<AzureBlobChunkUploadTarget> _signUpload(
    AzureBlobChunkSignRequest signRequest,
  ) async {
    final accessToken = _accessTokenProvider?.call();
    if (accessToken == null || accessToken.trim().isEmpty) {
      throw const AzureBlobChunkStorageException(
        'Your XMO session is unavailable. Sign in again before uploading media.',
      );
    }
    final request = await _httpClient.postUrl(signingEndpoint).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${accessToken.trim()}',
    );
    request.write(jsonEncode(signRequest.toJson()));
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    final decoded = body.trim().isEmpty ? null : jsonDecode(body);
    final json = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AzureBlobChunkStorageException(
        json['error']?.toString() ?? 'Azure chunk signing failed',
      );
    }
    if (json['success'] == false) {
      throw AzureBlobChunkStorageException(
        json['error']?.toString() ?? 'Azure chunk signing failed',
      );
    }
    return AzureBlobChunkUploadTarget.fromJson(json);
  }

  Future<void> _putBlob({
    required Uri uploadUrl,
    required Uint8List encryptedBytes,
    required String contentType,
  }) async {
    final request = await _httpClient.putUrl(uploadUrl).timeout(timeout);
    request.headers.set('x-ms-blob-type', 'BlockBlob');
    request.headers.contentType = ContentType.parse(contentType);
    request.headers.contentLength = encryptedBytes.length;
    request.add(encryptedBytes);
    final response = await request.close().timeout(timeout);
    await response.drain<void>().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AzureBlobChunkStorageException(
        'Azure chunk upload failed (${response.statusCode})',
      );
    }
  }
}

class AzureBlobChunkStorageException implements Exception {
  const AzureBlobChunkStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
