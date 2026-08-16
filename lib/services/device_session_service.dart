import 'package:matrix/matrix.dart';

import 'matrix_service.dart';

class DeviceSession {
  final Device device;
  final bool isCurrent;
  final bool isVerified;

  const DeviceSession({
    required this.device,
    required this.isCurrent,
    required this.isVerified,
  });
}

class DeviceReauthenticationRequired implements Exception {
  final String? session;

  const DeviceReauthenticationRequired(this.session);
}

class DeviceSessionService {
  final MatrixService _matrixService;

  DeviceSessionService(this._matrixService);

  Client get _client => _matrixService.client;

  Future<List<DeviceSession>> load() async {
    final devices = await _client.getDevices() ?? <Device>[];
    final userId = _client.userID;
    if (userId != null && _client.encryption != null) {
      try {
        await _client.updateUserDeviceKeys(additionalUsers: {userId});
      } catch (_) {
        // Device metadata remains useful if encryption key refresh is offline.
      }
    }
    final keyMap = userId == null
        ? const <String, DeviceKeys>{}
        : _client.userDeviceKeys[userId]?.deviceKeys ??
              const <String, DeviceKeys>{};

    final sessions = devices
        .map(
          (device) => DeviceSession(
            device: device,
            isCurrent: device.deviceId == _client.deviceID,
            isVerified: keyMap[device.deviceId]?.verified == true,
          ),
        )
        .toList();
    sessions.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      return (b.device.lastSeenTs ?? 0).compareTo(a.device.lastSeenTs ?? 0);
    });
    return sessions;
  }

  Future<void> rename(String deviceId, String displayName) async {
    await _client.updateDevice(deviceId, displayName: displayName.trim());
  }

  Future<void> delete(
    String deviceId, {
    AuthenticationData? auth,
    String? password,
    String? session,
  }) async {
    try {
      await _client.deleteDevice(
        deviceId,
        auth:
            auth ??
            (password == null
                ? null
                : AuthenticationPassword(
                    session: session,
                    password: password,
                    identifier: AuthenticationUserIdentifier(
                      user: _client.userID!,
                    ),
                  )),
      );
    } on MatrixException catch (error) {
      if (error.requireAdditionalAuthentication &&
          password == null &&
          auth == null) {
        throw DeviceReauthenticationRequired(error.session);
      }
      rethrow;
    }
  }

  Future<void> deleteAllOther({
    AuthenticationData? auth,
    String? password,
    String? session,
  }) async {
    final ids = (await _client.getDevices() ?? <Device>[])
        .where((device) => device.deviceId != _client.deviceID)
        .map((device) => device.deviceId)
        .toList();
    if (ids.isEmpty) return;

    try {
      await _client.deleteDevices(
        ids,
        auth:
            auth ??
            (password == null
                ? null
                : AuthenticationPassword(
                    session: session,
                    password: password,
                    identifier: AuthenticationUserIdentifier(
                      user: _client.userID!,
                    ),
                  )),
      );
    } on MatrixException catch (error) {
      if (error.requireAdditionalAuthentication &&
          password == null &&
          auth == null) {
        throw DeviceReauthenticationRequired(error.session);
      }
      rethrow;
    }
  }
}
