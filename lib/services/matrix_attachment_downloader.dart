import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import 'matrix_encrypted_media_helper.dart';

class MatrixAttachmentDownloader {
  const MatrixAttachmentDownloader({
    MatrixEncryptedMediaHelper encryptedMediaHelper =
        const MatrixEncryptedMediaHelper(),
  }) : _encryptedMediaHelper = encryptedMediaHelper;

  final MatrixEncryptedMediaHelper _encryptedMediaHelper;

  Future<MatrixFile> download(
    Event event, {
    bool getThumbnail = false,
    Future<Uint8List> Function(Uri)? downloadCallback,
    bool fromLocalStoreOnly = false,
  }) async {
    if (![EventTypes.Message, EventTypes.Sticker].contains(event.type)) {
      throw "This event has the type '${event.type}' and so it can't contain an attachment.";
    }
    if (event.status.isSending) {
      final localFile = event.room.sendingFilePlaceholders[event.eventId];
      if (localFile != null) return localFile;
    }

    final mxcUrl =
        event.attachmentOrThumbnailMxcUrl(getThumbnail: getThumbnail);
    if (mxcUrl == null) {
      throw "This event hasn't any attachment or thumbnail.";
    }

    final resolvedGetThumbnail = mxcUrl != event.attachmentMxcUrl;
    final isEncrypted = resolvedGetThumbnail
        ? event.isThumbnailEncrypted
        : event.isAttachmentEncrypted;
    if (!isEncrypted) {
      return event.downloadAndDecryptAttachment(
        getThumbnail: getThumbnail,
        downloadCallback: downloadCallback,
        fromLocalStoreOnly: fromLocalStoreOnly,
      );
    }
    if (!event.room.client.encryptionEnabled) {
      throw 'Encryption is not enabled in your Client.';
    }

    final encryptedBytes = await _downloadEncryptedBytes(
      event,
      mxcUrl: mxcUrl,
      getThumbnail: resolvedGetThumbnail,
      downloadCallback: downloadCallback,
      fromLocalStoreOnly: fromLocalStoreOnly,
    );
    final encryptedFile = _encryptedFileFromEvent(
      event,
      encryptedBytes,
      getThumbnail: resolvedGetThumbnail,
    );
    final bytes = await _encryptedMediaHelper.decrypt(encryptedFile);
    if (bytes == null) {
      throw 'Unable to decrypt file';
    }

    final mimeType = resolvedGetThumbnail
        ? event.thumbnailMimetype
        : event.attachmentMimetype;
    return MatrixFile(
      bytes: bytes,
      name: event.body.isNotEmpty ? event.body : 'attachment',
      mimeType: mimeType.isNotEmpty ? mimeType : null,
    );
  }

  Future<Uint8List> _downloadEncryptedBytes(
    Event event, {
    required Uri mxcUrl,
    required bool getThumbnail,
    required Future<Uint8List> Function(Uri)? downloadCallback,
    required bool fromLocalStoreOnly,
  }) async {
    final database = event.room.client.database;
    final infoMap = getThumbnail ? event.thumbnailInfoMap : event.infoMap;
    var storeable = database != null &&
        infoMap['size'] is int &&
        infoMap['size'] <= database.maxFileSize;

    Uint8List? bytes;
    if (storeable) {
      bytes = await database.getFile(mxcUrl);
    }

    if (bytes == null && fromLocalStoreOnly) {
      throw 'Unable to download file from local store.';
    }
    if (bytes == null) {
      final callback = downloadCallback ??
          (Uri url) async =>
              (await event.room.client.httpClient.get(url)).bodyBytes;
      bytes = await callback(_downloadUri(event, mxcUrl));
      storeable = database != null &&
          storeable &&
          bytes.lengthInBytes < database.maxFileSize;
      if (storeable) {
        await database.storeFile(
          mxcUrl,
          bytes,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    return bytes;
  }

  EncryptedFile _encryptedFileFromEvent(
    Event event,
    Uint8List bytes, {
    required bool getThumbnail,
  }) {
    final fileMap =
        getThumbnail ? event.infoMap['thumbnail_file'] : event.content['file'];
    if (fileMap is! Map) {
      throw 'Missing encrypted file metadata.';
    }

    final keyMap = fileMap['key'];
    if (keyMap is! Map) {
      throw 'Missing encrypted file key metadata.';
    }

    final keyOps = keyMap['key_ops'];
    if (keyOps is List && !keyOps.contains('decrypt')) {
      throw "Missing 'decrypt' in 'key_ops'.";
    }

    final iv = fileMap['iv'];
    final key = keyMap['k'];
    final hashes = fileMap['hashes'];
    final sha256 = hashes is Map ? hashes['sha256'] : null;
    if (iv is! String || key is! String || sha256 is! String) {
      throw 'Invalid encrypted file metadata.';
    }

    return EncryptedFile(
      data: bytes,
      iv: iv,
      k: key,
      sha256: sha256,
    );
  }

  Uri _downloadUri(Event event, Uri mxcUrl) {
    if (!mxcUrl.isScheme('mxc')) return mxcUrl;
    final homeserver = event.room.client.homeserver;
    if (homeserver == null) return Uri();
    return homeserver.resolve(
      '_matrix/media/v3/download/${mxcUrl.host}'
      '${mxcUrl.hasPort ? ':${mxcUrl.port}' : ''}${mxcUrl.path}',
    );
  }
}
