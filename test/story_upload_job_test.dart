import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/story_models.dart';
import 'package:xmo/services/story_upload_queue_service.dart';

void main() {
  StoryUploadJob job({
    StoryUploadStatus status = StoryUploadStatus.queued,
    StoryCreationPhase phase = StoryCreationPhase.preparing,
    int uploadedBytes = 0,
    int totalBytes = 0,
    int attempts = 0,
    DateTime? nextRetryAt,
  }) {
    final now = DateTime.utc(2026, 8, 2);
    return StoryUploadJob(
      id: 'story-request-1',
      ownerUserId: '@alice:example.org',
      mediaType: StoryMediaType.video,
      mediaPath: '/queue/story.media',
      mediaSizeBytes: 1024,
      mediaMimeType: 'video/mp4',
      mediaFileName: 'story.mp4',
      thumbnailPath: '/queue/story.thumbnail',
      caption: 'Caption',
      privacy: StoryPrivacy.contactsExcept,
      customPrivacyList: const ['@blocked:example.org'],
      status: status,
      phase: phase,
      uploadedBytes: uploadedBytes,
      totalBytes: totalBytes,
      attempts: attempts,
      createdAt: now,
      updatedAt: now,
      nextRetryAt: nextRetryAt,
    );
  }

  test('persists the complete story publish request', () {
    final source = job(
      status: StoryUploadStatus.failed,
      phase: StoryCreationPhase.uploadingMedia,
      uploadedBytes: 256,
      totalBytes: 1024,
      attempts: 1,
      nextRetryAt: DateTime.utc(2026, 8, 2, 0, 0, 2),
    );

    final restored = StoryUploadJob.fromJson(source.toJson());

    expect(restored.ownerUserId, source.ownerUserId);
    expect(restored.mediaType, StoryMediaType.video);
    expect(restored.mediaPath, source.mediaPath);
    expect(restored.thumbnailPath, source.thumbnailPath);
    expect(restored.caption, source.caption);
    expect(restored.privacy, StoryPrivacy.contactsExcept);
    expect(restored.customPrivacyList, source.customPrivacyList);
    expect(restored.progress, 0.25);
    expect(restored.shouldAutoRetry, isTrue);
  });

  test('a process-interrupted running job restores as queued', () {
    final restored = StoryUploadJob.fromJson(
      job(status: StoryUploadStatus.running).toJson(),
    );

    expect(restored.status, StoryUploadStatus.queued);
    expect(restored.isVisible, isTrue);
  });

  test('publishing phases expose useful global progress', () {
    expect(job(phase: StoryCreationPhase.uploadingThumbnail).progress, 0.9);
    expect(job(phase: StoryCreationPhase.publishing).progress, 0.95);
    expect(job().progress, isNull);
  });

  test('completed and cancelled jobs are hidden from global progress', () {
    expect(job(status: StoryUploadStatus.completed).isVisible, isFalse);
    expect(job(status: StoryUploadStatus.cancelled).isVisible, isFalse);
    expect(job(status: StoryUploadStatus.failed).isVisible, isTrue);
  });
}
