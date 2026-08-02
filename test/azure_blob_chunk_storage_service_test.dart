import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/azure_blob_chunk_storage_service.dart';

void main() {
  group('AzureBlobChunkStorageService', () {
    test('signs and uploads encrypted chunk bytes', () async {
      AzureBlobChunkSignRequest? signedRequest;
      Uri? uploadedUrl;
      Uint8List? uploadedBytes;
      String? uploadedContentType;
      final encryptedBytes = Uint8List.fromList([8, 7, 6, 5]);
      final service = AzureBlobChunkStorageService(
        signingEndpoint: Uri.parse('https://auth.example.test/sign'),
        signer: (request) async {
          signedRequest = request;
          return AzureBlobChunkUploadTarget(
            uploadUrl: Uri.parse('https://blob.example.test/upload?sas=write'),
            downloadUrl:
                Uri.parse('https://blob.example.test/download?sas=read'),
          );
        },
        uploader: ({
          required uploadUrl,
          required encryptedBytes,
          required contentType,
        }) async {
          uploadedUrl = uploadUrl;
          uploadedBytes = encryptedBytes;
          uploadedContentType = contentType;
        },
      );

      final downloadUrl = await service.uploadEncryptedChunk(
        encryptedBytes: encryptedBytes,
        fileName: 'video.mp4.xmo-stream.0.chunk',
        contentType: 'application/octet-stream',
        chunkIndex: 0,
        roomId: '!room:example.test',
      );

      expect(downloadUrl.toString(),
          'https://blob.example.test/download?sas=read');
      expect(signedRequest!.fileName, 'video.mp4.xmo-stream.0.chunk');
      expect(signedRequest!.contentType, 'application/octet-stream');
      expect(signedRequest!.size, encryptedBytes.length);
      expect(signedRequest!.chunkIndex, 0);
      expect(signedRequest!.roomId, '!room:example.test');
      expect(signedRequest!.cipherSha256, isNotEmpty);
      expect(
          uploadedUrl.toString(), 'https://blob.example.test/upload?sas=write');
      expect(uploadedBytes, encryptedBytes);
      expect(uploadedContentType, 'application/octet-stream');
    });

    test('rejects missing signer URLs', () {
      expect(
        () => AzureBlobChunkUploadTarget.fromJson({
          'success': true,
          'uploadUrl': '',
          'downloadUrl': 'https://blob.example.test/download',
        }),
        throwsFormatException,
      );
    });

    test('sends Matrix authorization and room-bound integrity context',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic>? requestBody;
      String? authorization;
      final handled = server.first.then((request) async {
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        requestBody = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': true,
          'uploadUrl': 'https://blob.example.test/upload?write=short',
          'downloadUrl':
              'https://matrix.example.test/auth/media/chunks/azure/download?ref=opaque',
        }));
        await request.response.close();
      });
      final service = AzureBlobChunkStorageService(
        signingEndpoint: Uri.parse(
          'http://${server.address.host}:${server.port}/sign',
        ),
        accessTokenProvider: () => 'matrix-token',
        uploader: ({
          required uploadUrl,
          required encryptedBytes,
          required contentType,
        }) async {},
      );

      try {
        await service.uploadEncryptedChunk(
          encryptedBytes: Uint8List.fromList([1, 2, 3, 4]),
          fileName: 'video.chunk',
          contentType: 'application/octet-stream',
          chunkIndex: 2,
          roomId: '!secure:example.test',
        );
        await handled;

        expect(authorization, 'Bearer matrix-token');
        expect(requestBody?['roomId'], '!secure:example.test');
        expect(requestBody?['cipherSha256'], isNotEmpty);
      } finally {
        service.close();
        await server.close(force: true);
      }
    });

    test('rejects real signing without a Matrix access token', () async {
      final service = AzureBlobChunkStorageService(
        signingEndpoint: Uri.parse('https://auth.example.test/sign'),
      );
      addTearDown(service.close);

      await expectLater(
        service.uploadEncryptedChunk(
          encryptedBytes: Uint8List.fromList([1]),
          fileName: 'video.chunk',
          contentType: 'application/octet-stream',
          chunkIndex: 0,
          roomId: '!secure:example.test',
        ),
        throwsA(isA<AzureBlobChunkStorageException>()),
      );
    });
  });
}
