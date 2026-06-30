import 'dart:typed_data';

import '../services/matrix_service.dart';

class MediaRepository {
  const MediaRepository(this.matrixService);

  final MatrixService matrixService;

  Future<void> sendMessage(String roomId, String message) =>
      matrixService.mediaRepository.sendMessage(roomId, message);

  Future<void> sendFileWithProgress({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
  }) =>
      matrixService.mediaRepository.sendFileWithProgress(
        roomId: roomId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        onUploadProgress: onUploadProgress,
        isCancelled: isCancelled,
      );

  Future<void> sendImageWithCaption({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String caption = '',
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
  }) =>
      matrixService.mediaRepository.sendImageWithCaption(
        roomId: roomId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        caption: caption,
        onUploadProgress: onUploadProgress,
        isCancelled: isCancelled,
      );
}
