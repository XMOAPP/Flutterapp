import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/message_reply_reference.dart';
import 'package:xmo/services/transfer_queue_service.dart';

void main() {
  TransferJob job({
    TransferStatus status = TransferStatus.queued,
    int uploadedBytes = 0,
    int totalBytes = 100,
    int attempts = 0,
    DateTime? retryAt,
    MessageReplyReference? replyReference,
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
      replyReference: replyReference,
    );
  }

  test('persists all transfer state needed for a resumed queue', () {
    const replyReference = MessageReplyReference(
      roomId: '!room:example.org',
      eventId: r'$reply:example.org',
    );
    final source = job(
      status: TransferStatus.failed,
      uploadedBytes: 25,
      attempts: 2,
      retryAt: DateTime.utc(2026, 6, 21, 0, 0, 4),
      replyReference: replyReference,
    );
    final restored = TransferJob.fromJson(source.toJson());

    expect(restored.ownerUserId, source.ownerUserId);
    expect(restored.status, TransferStatus.failed);
    expect(restored.progress, 0.25);
    expect(restored.shouldAutoRetry, isTrue);
    expect(restored.replyReference?.eventId, replyReference.eventId);
    expect(restored.replyReference?.roomId, replyReference.roomId);
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

  test('auto retry requires a scheduled retry before max attempts', () {
    expect(
      job(
        status: TransferStatus.failed,
        attempts: 1,
        retryAt: DateTime.utc(2026, 6, 21, 0, 0, 2),
      ).shouldAutoRetry,
      isTrue,
    );
    expect(
      job(
        status: TransferStatus.failed,
        attempts: 3,
        retryAt: DateTime.utc(2026, 6, 21, 0, 0, 8),
      ).shouldAutoRetry,
      isFalse,
    );
    expect(job(status: TransferStatus.running).shouldAutoRetry, isFalse);
  });

  test('copyWith can clear retry and error state for manual retry', () {
    final failed = job(
      status: TransferStatus.failed,
      uploadedBytes: 40,
      attempts: 2,
      retryAt: DateTime.utc(2026, 6, 21, 0, 0, 4),
    ).copyWith(error: 'network');

    final retried = failed.copyWith(
      status: TransferStatus.queued,
      uploadedBytes: 0,
      clearError: true,
      clearNextRetryAt: true,
    );

    expect(retried.status, TransferStatus.queued);
    expect(retried.uploadedBytes, 0);
    expect(retried.error, isNull);
    expect(retried.nextRetryAt, isNull);
  });
}
