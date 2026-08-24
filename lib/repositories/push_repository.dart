import '../services/matrix_service.dart';

class PushRepository {
  const PushRepository(this.matrixService);

  final MatrixService matrixService;

  Future<void> setHttpPusher({
    required String pushKey,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    required String profileTag,
    required String pushGatewayUrl,
    String lang = 'en',
  }) => matrixService.pushRepository.setHttpPusher(
    pushKey: pushKey,
    appId: appId,
    appDisplayName: appDisplayName,
    deviceDisplayName: deviceDisplayName,
    profileTag: profileTag,
    pushGatewayUrl: pushGatewayUrl,
    lang: lang,
  );

  Future<void> removeHttpPusher({
    required String pushKey,
    required String appId,
  }) => matrixService.pushRepository.removeHttpPusher(
    pushKey: pushKey,
    appId: appId,
  );
}
