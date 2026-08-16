class MediaUploadPolicy {
  const MediaUploadPolicy._();

  static const int maxUploadBytes = 50 * 1024 * 1024;
  static const String maxUploadLabel = '50 MB';
  static const String oversizedMessage =
      'Files larger than 50 MB cannot be sent.';

  static bool allows(int sizeInBytes) =>
      sizeInBytes > 0 && sizeInBytes <= maxUploadBytes;

  static void validate(int sizeInBytes) {
    if (sizeInBytes <= 0) {
      throw const MediaUploadPolicyException('The selected file is empty.');
    }
    if (sizeInBytes > maxUploadBytes) {
      throw const MediaUploadPolicyException(oversizedMessage);
    }
  }
}

class MediaUploadPolicyException implements Exception {
  const MediaUploadPolicyException(this.message);

  final String message;

  @override
  String toString() => message;
}
