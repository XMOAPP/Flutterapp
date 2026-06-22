import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/transfer_queue_service.dart';

void main() {
  TransferJob job({
    TransferStatus status = TransferStatus.queued,
    int uploadedBytes = 0,
    int totalBytes = 100,
    int attempts = 0,
    DateTime? retryAt,
  }) {
    final now = DateTime.utc(2026, 6, 21);
    return TransferJob(
      id: 'job-1',
      direction: TransferDirection.upload,
      kind: TransferKind.photo,
      ownerUserId: '@alice:example.org',
      roomId: '!room:example.org',
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      localPath: '/tmp/photo.jpg',
      totalBytes: totalBytes,
      uploadedBytes: uploadedBytes,
      attempts: attempts,
      status: status,
      createdAt: now,
      updatedAt: now,
      nextRetryAt: retryAt,
    );
  }

  test('persists all transfer state needed for a resumed queue', () {
    final source = job(
      status: TransferStatus.failed,
      uploadedBytes: 25,
      attempts: 2,
      retryAt: DateTime.utc(2026, 6, 21, 0, 0, 4),
    );
    final restored = TransferJob.fromJson(source.toJson());

    expect(restored.ownerUserId, source.ownerUserId);
    expect(restored.status, TransferStatus.failed);
    expect(restored.progress, 0.25);
    expect(restored.shouldAutoRetry, isTrue);
  });

  test('cancelled and failed jobs are retryable, active jobs are cancellable',
      () {
    expect(job(status: TransferStatus.cancelled).canRetry, isTrue);
    expect(job(status: TransferStatus.failed).canRetry, isTrue);
    expect(job(status: TransferStatus.running).canCancel, isTrue);
    expect(job(status: TransferStatus.completed).canCancel, isFalse);
  });

  test('unknown total size reports indeterminate progress', () {
    expect(job(totalBytes: 0).progress, isNull);
  });
}
