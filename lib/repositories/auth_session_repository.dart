import 'dart:typed_data';

import '../services/matrix_service.dart';

class AuthSessionRepository {
  const AuthSessionRepository(this.matrixService);

  final MatrixService matrixService;

  bool get isLoggedIn => matrixService.sessionRepository.isLoggedIn;
  String? get userId => matrixService.sessionRepository.userId;
  String? get displayName => matrixService.sessionRepository.displayName;
  String? get avatarUrl => matrixService.sessionRepository.avatarUrl;

  Future<void> init() => matrixService.sessionRepository.init();
  Future<void> login(String username, String password) =>
      matrixService.sessionRepository.login(username, password);
  Future<void> register(String username, String password) =>
      matrixService.sessionRepository.register(username, password);
  Future<void> logout() => matrixService.sessionRepository.logout();
  Future<void> refreshProfile() =>
      matrixService.sessionRepository.refreshProfile();
  Future<void> updateProfile({
    required String displayName,
    Uint8List? avatarBytes,
    String avatarFileName = 'avatar.jpg',
    bool removeAvatar = false,
  }) =>
      matrixService.sessionRepository.updateProfile(
        displayName: displayName,
        avatarBytes: avatarBytes,
        avatarFileName: avatarFileName,
        removeAvatar: removeAvatar,
      );
}
