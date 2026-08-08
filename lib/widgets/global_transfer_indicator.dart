import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/story_upload_queue_service.dart';
import '../services/transfer_queue_service.dart';
import '../services/visible_chat_route_service.dart';
import '../theme.dart';

bool _isActiveUpload(TransferJob job) {
  if (job.direction != TransferDirection.upload) return false;
  return job.status == TransferStatus.queued ||
      job.status == TransferStatus.running ||
      job.status == TransferStatus.paused ||
      job.status == TransferStatus.failed;
}

@visibleForTesting
List<TransferJob> visibleTransferUploadsForIndicator(List<TransferJob> jobs) {
  final accountUploads = jobs
      .where((job) => job.direction == TransferDirection.upload)
      .toList(growable: false);
  final activeBatchIds = accountUploads
      .where(_isActiveUpload)
      .map((job) => job.batchId)
      .whereType<String>()
      .toSet();
  return accountUploads.where((job) {
    if (_isActiveUpload(job)) return true;
    return job.status == TransferStatus.completed &&
        job.batchId != null &&
        activeBatchIds.contains(job.batchId);
  }).toList();
}

@visibleForTesting
double? calculateByteWeightedUploadProgress(
  Iterable<({int uploaded, int total})> items,
) {
  final values = items.toList(growable: false);
  if (values.isEmpty || values.any((item) => item.total <= 0)) return null;
  final total = values.fold<int>(0, (sum, item) => sum + item.total);
  if (total <= 0) return null;
  final uploaded = values.fold<int>(0, (sum, item) => sum + item.uploaded);
  return (uploaded / total).clamp(0.0, 1.0).toDouble();
}

@visibleForTesting
String transferStageLabel(TransferStage stage) => switch (stage) {
  TransferStage.preparing => 'Preparing',
  TransferStage.compressing => 'Compressing',
  TransferStage.encrypting => 'Encrypting',
  TransferStage.connecting => 'Connecting',
  TransferStage.uploading => 'Uploading',
  TransferStage.finalizing => 'Finalizing',
};

class GlobalTransferIndicator extends StatelessWidget {
  final ValueChanged<String>? onOpenChat;

  const GlobalTransferIndicator({super.key, this.onOpenChat});

  @override
  Widget build(BuildContext context) {
    final transferQueue = TransferQueueService.instance;
    final storyQueue = StoryUploadQueueService.instance;
    return ValueListenableBuilder<String?>(
      valueListenable: VisibleChatRouteService.instance.roomId,
      builder: (context, visibleRoomId, _) {
        return StreamBuilder<List<TransferJob>>(
          stream: transferQueue.stream,
          initialData: transferQueue.jobs,
          builder: (context, transferSnapshot) {
            return StreamBuilder<List<StoryUploadJob>>(
              stream: storyQueue.stream,
              initialData: storyQueue.jobs,
              builder: (context, storySnapshot) {
                final uploads = visibleTransferUploadsForIndicator(
                  transferSnapshot.data ?? const <TransferJob>[],
                )..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                final storyUploads =
                    (storySnapshot.data ?? const <StoryUploadJob>[])
                        .where((job) => job.isVisible)
                        .toList(growable: false)
                      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                return _buildIndicator(uploads, storyUploads, visibleRoomId);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildIndicator(
    List<TransferJob> uploads,
    List<StoryUploadJob> storyUploads,
    String? visibleRoomId,
  ) {
    final uploadCount = uploads.length + storyUploads.length;
    if (uploadCount == 0) return const SizedBox.shrink();

    final failedTransfers = uploads
        .where((job) => job.status == TransferStatus.failed)
        .toList(growable: false);
    final failedStories = storyUploads
        .where((job) => job.status == StoryUploadStatus.failed)
        .toList(growable: false);
    final failedCount = failedTransfers.length + failedStories.length;
    final hasScheduledRetry =
        uploads.any((job) => job.shouldAutoRetry) ||
        storyUploads.any((job) => job.shouldAutoRetry);
    final progressValues = <double>[
      ...uploads.map((job) => job.progress).whereType<double>(),
      ...storyUploads.map((job) => job.progress).whereType<double>(),
    ];
    final byteProgress = <({int uploaded, int total})>[
      ...uploads.map(
        (job) => (uploaded: job.uploadedBytes, total: job.totalBytes),
      ),
      ...storyUploads.map(
        (job) => (uploaded: job.uploadedBytes, total: job.totalBytes),
      ),
    ];
    final weightedProgress = calculateByteWeightedUploadProgress(byteProgress);
    final progress =
        weightedProgress ??
        (progressValues.isEmpty
            ? null
            : progressValues.reduce((a, b) => a + b) / progressValues.length);
    final activeTransfer = _firstTransferWhere(
      uploads,
      (job) => job.status != TransferStatus.completed,
    );
    final title = failedCount > 0
        ? '$failedCount upload${failedCount == 1 ? '' : 's'} failed'
        : storyUploads.length == 1 && uploads.isEmpty
        ? 'Uploading story'
        : uploads.length == 1 && storyUploads.isEmpty
        ? 'Uploading ${uploads.first.fileName}'
        : 'Uploading $uploadCount items';
    final hasVisibleTransferStage =
        activeTransfer != null &&
        activeTransfer.stage != TransferStage.uploading;
    final status = failedCount > 0
        ? hasScheduledRetry
              ? 'Retrying shortly'
              : failedStories.isNotEmpty
              ? 'Upload failed'
              : 'Open chat to retry'
        : hasVisibleTransferStage
        ? transferStageLabel(activeTransfer.stage)
        : progress == null
        ? 'Preparing'
        : '${(progress * 100).round()}%';
    final retryableStory = _firstStoryWhere(
      failedStories,
      (job) => !job.shouldAutoRetry,
    );
    final cancellableStory = _firstStoryWhere(
      storyUploads,
      (job) =>
          job.status == StoryUploadStatus.queued ||
          job.status == StoryUploadStatus.running,
    );
    final isViewingUploadingChat =
        visibleRoomId != null &&
        uploads.any((job) => job.roomId == visibleRoomId);
    final targetChatUpload = isViewingUploadingChat
        ? null
        : _firstTransferWhere(
            uploads,
            (job) => job.status != TransferStatus.completed,
          );

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 72),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: kWhite,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x52000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 46,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LinearProgressIndicator(
                            value: failedCount > 0 ? 0.0 : progress,
                            color: failedCount > 0 ? Colors.red : kLimeGreen,
                            backgroundColor: kWhite,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 18,
                                  color: kBlack,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: kBlack,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  status,
                                  maxLines: 1,
                                  style: GoogleFonts.inter(
                                    color: kDarkGrey,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (retryableStory != null) ...[
                                  const SizedBox(width: 2),
                                  IconButton(
                                    onPressed: () => StoryUploadQueueService
                                        .instance
                                        .retry(retryableStory.id),
                                    icon: const Icon(
                                      Icons.refresh,
                                      size: 18,
                                      semanticLabel: 'Retry story upload',
                                    ),
                                    color: kBlack,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 32,
                                      height: 32,
                                    ),
                                  ),
                                ] else if (cancellableStory != null) ...[
                                  const SizedBox(width: 2),
                                  IconButton(
                                    onPressed: () => StoryUploadQueueService
                                        .instance
                                        .cancel(cancellableStory.id),
                                    icon: const Icon(
                                      Icons.close,
                                      size: 18,
                                      semanticLabel: 'Cancel story upload',
                                    ),
                                    color: kBlack,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 32,
                                      height: 32,
                                    ),
                                  ),
                                ],
                                if (targetChatUpload != null &&
                                    onOpenChat != null) ...[
                                  const SizedBox(width: 2),
                                  IconButton(
                                    onPressed: () =>
                                        onOpenChat!(targetChatUpload.roomId),
                                    icon: const Icon(
                                      Icons.chevron_right,
                                      size: 21,
                                      semanticLabel: 'Open uploading chat',
                                    ),
                                    color: kBlack,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 32,
                                      height: 32,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  StoryUploadJob? _firstStoryWhere(
    Iterable<StoryUploadJob> jobs,
    bool Function(StoryUploadJob job) test,
  ) {
    for (final job in jobs) {
      if (test(job)) return job;
    }
    return null;
  }

  TransferJob? _firstTransferWhere(
    Iterable<TransferJob> jobs,
    bool Function(TransferJob job) test,
  ) {
    for (final job in jobs) {
      if (test(job)) return job;
    }
    return null;
  }
}
