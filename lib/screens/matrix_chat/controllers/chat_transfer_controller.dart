/// UI state for queued chat uploads.
///
/// Transfer persistence and retry policy remain in TransferQueueService. This
/// controller only owns state which must be discarded with a chat screen.
class ChatTransferController<TUpload, TAlbum> {
  final List<TUpload> uploads = <TUpload>[];
  final List<TAlbum> albums = <TAlbum>[];
  final Set<String> cancelledUploadIds = <String>{};
  final Map<String, DateTime> progressUiUpdates = <String, DateTime>{};

  bool get hasPendingWork => uploads.isNotEmpty || albums.isNotEmpty;

  void cancel(String id) => cancelledUploadIds.add(id);

  bool isCancelled(String id) => cancelledUploadIds.contains(id);

  void clearProgress(String id) => progressUiUpdates.remove(id);
}
