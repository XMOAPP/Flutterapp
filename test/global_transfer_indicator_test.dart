import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/transfer_queue_service.dart';
import 'package:xmo/widgets/global_transfer_indicator.dart';

void main() {
  TransferJob job({
    required String id,
    required TransferStatus status,
    required int uploadedBytes,
    required int totalBytes,
    String? batchId,
  }) {
    final now = DateTime.utc(2026, 8, 2);
    return TransferJob(
      id: id,
      direction: TransferDirection.upload,
      kind: TransferKind.file,
      ownerUserId: '@alice:example.org',
      roomId: '!room:example.org',
      fileName: '$id.bin',
      mimeType: 'application/octet-stream',
      localPath: '/tmp/$id.bin',
      totalBytes: totalBytes,
      uploadedBytes: uploadedBytes,
      status: status,
      createdAt: now,
      updatedAt: now,
      batchId: batchId,
    );
  }

  test('weights combined progress by bytes instead of item count', () {
    final progress = calculateByteWeightedUploadProgress([
      (uploaded: 1, total: 1),
      (uploaded: 40, total: 100),
    ]);

    expect(progress, closeTo(41 / 101, 0.000001));
  });

  test('exposes concise labels for persisted preparation stages', () {
    expect(transferStageLabel(TransferStage.preparing), 'Preparing');
    expect(transferStageLabel(TransferStage.compressing), 'Compressing');
    expect(transferStageLabel(TransferStage.encrypting), 'Encrypting');
    expect(transferStageLabel(TransferStage.connecting), 'Connecting');
    expect(transferStageLabel(TransferStage.uploading), 'Uploading');
    expect(transferStageLabel(TransferStage.finalizing), 'Finalizing');
  });

  test('keeps completed batch members visible while a sibling is active', () {
    final completed = job(
      id: 'small',
      status: TransferStatus.completed,
      uploadedBytes: 10,
      totalBytes: 10,
      batchId: 'batch-1',
    );
    final queued = job(
      id: 'large',
      status: TransferStatus.queued,
      uploadedBytes: 0,
      totalBytes: 90,
      batchId: 'batch-1',
    );

    expect(
      visibleTransferUploadsForIndicator([completed, queued]),
      containsAll([completed, queued]),
    );
    expect(
      visibleTransferUploadsForIndicator([
        completed,
        queued.copyWith(status: TransferStatus.completed),
      ]),
      isEmpty,
    );
  });
}
