import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/config/media_upload_policy.dart';

void main() {
  group('MediaUploadPolicy', () {
    test('accepts files up to and including 50 MiB', () {
      expect(MediaUploadPolicy.allows(1), isTrue);
      expect(
        MediaUploadPolicy.allows(MediaUploadPolicy.maxUploadBytes),
        isTrue,
      );
      expect(
        () => MediaUploadPolicy.validate(MediaUploadPolicy.maxUploadBytes),
        returnsNormally,
      );
    });

    test('rejects empty and oversized files', () {
      expect(
        () => MediaUploadPolicy.validate(0),
        throwsA(isA<MediaUploadPolicyException>()),
      );
      expect(
        () => MediaUploadPolicy.validate(MediaUploadPolicy.maxUploadBytes + 1),
        throwsA(isA<MediaUploadPolicyException>()),
      );
    });
  });
}
