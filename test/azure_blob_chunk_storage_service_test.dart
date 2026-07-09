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
      );

      expect(downloadUrl.toString(),
          'https://blob.example.test/download?sas=read');
      expect(signedRequest!.fileName, 'video.mp4.xmo-stream.0.chunk');
      expect(signedRequest!.contentType, 'application/octet-stream');
      expect(signedRequest!.size, encryptedBytes.length);
      expect(signedRequest!.chunkIndex, 0);
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
  });
}
