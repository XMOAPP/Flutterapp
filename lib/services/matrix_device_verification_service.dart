import 'package:matrix/matrix.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

import 'e2ee_service.dart';
import 'matrix_service.dart';

class MatrixDeviceVerificationService {
  MatrixDeviceVerificationService(this._matrixService);

  final MatrixService _matrixService;

  Client get _client => _matrixService.client;

  Stream<KeyVerification> get incomingRequests =>
      _client.onKeyVerificationRequest.stream;

  Future<KeyVerification> startVerification(String deviceId) async {
    final userId = _client.userID;
    if (userId == null || _client.encryption?.enabled != true) {
      throw StateError('Encryption is not available for this session.');
    }
    if (deviceId == _client.deviceID) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Cannot verify this device',
      );
    }

    await _client.updateUserDeviceKeys(additionalUsers: {userId});
    final device = _client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    if (device == null) {
      throw StateError(
        'Encryption keys for this device are not available yet.',
      );
    }
    if (device.verified) {
      throw StateError('This device is already verified.');
    }
    return device.startVerification();
  }

  Future<E2eeStatus> requestRecoverySecrets() async {
    final verificationService = E2eeService(_matrixService);
    await verificationService.requestSecretsFromVerifiedDevices();
    return verificationService.getStatus();
  }
}
