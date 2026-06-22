import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import '../../models/invite_link_models.dart';
import 'matrix_repository_contracts.dart';

class MatrixSdkSessionRepository implements MatrixSessionRepository {
  MatrixSdkSessionRepository(this._api);
  final MatrixRepositoryApi _api;

  @override
  String? get avatarUrl => _api.avatarUrl;
  @override
  String? get displayName => _api.displayName;
  @override
  bool get isLoggedIn => _api.isLoggedIn;
  @override
  String? get userId => _api.userId;
  @override
  Future<void> init() => _api.init();
  @override
  Future<void> login(String username, String password) =>
      _api.login(username, password);
  @override
  Future<void> refreshProfile() => _api.refreshProfile();
  @override
  Future<void> register(String username, String password) =>
      _api.register(username, password);
  @override
  Future<void> logout() => _api.logout();
  @override
  Future<void> updateProfile({
    required String displayName,
    Uint8List? avatarBytes,
    String avatarFileName = 'avatar.jpg',
    bool removeAvatar = false,
  }) =>
      _api.updateProfile(
        displayName: displayName,
        avatarBytes: avatarBytes,
        avatarFileName: avatarFileName,
        removeAvatar: removeAvatar,
      );
}

class MatrixSdkRoomRepository implements MatrixRoomRepository {
  MatrixSdkRoomRepository(this._api);
  final MatrixRepositoryApi _api;

  @override
  List<Room> getRooms() => _api.getRooms();
  @override
  Future<String> createChannel({
    required String name,
    String? topic,
    bool isPublic = true,
  }) =>
      _api.createChannel(
        name: name,
        isPublic: isPublic,
        topic: topic,
      );
  @override
  Future<String> createDirectRoom(String userId) =>
      _api.createDirectRoom(userId);
  @override
  Future<String> createRoom({
    required String name,
    String? topic,
    bool isDirect = false,
  }) =>
      _api.createRoom(
        name: name,
        topic: topic,
        isDirect: isDirect,
      );
  @override
  Future<Timeline?> getTimeline(String roomId) => _api.getTimeline(roomId);
  @override
  Future<void> joinRoom(String roomIdOrAlias) => _api.joinRoom(roomIdOrAlias);
}

class MatrixSdkMediaRepository implements MatrixMediaRepository {
  MatrixSdkMediaRepository(this._api);
  final MatrixRepositoryApi _api;

  @override
  Future<void> sendMessage(String roomId, String message) =>
      _api.sendMessage(roomId, message);
  @override
  Future<void> sendFileWithProgress({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
  }) =>
      _api.sendFileWithProgress(
        roomId: roomId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        onUploadProgress: onUploadProgress,
        isCancelled: isCancelled,
      );
  @override
  Future<void> sendImageWithCaption({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String caption = '',
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
  }) =>
      _api.sendImageWithCaption(
        roomId: roomId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        caption: caption,
        onUploadProgress: onUploadProgress,
        isCancelled: isCancelled,
      );
}

class MatrixSdkPushRepository implements MatrixPushRepository {
  MatrixSdkPushRepository(this._api);
  final MatrixRepositoryApi _api;

  @override
  Future<void> removeHttpPusher(
          {required String pushKey, required String appId}) =>
      _api.removeHttpPusher(pushKey: pushKey, appId: appId);
  @override
  Future<void> setHttpPusher({
    required String pushKey,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    required String profileTag,
    required String pushGatewayUrl,
    String lang = 'en',
  }) =>
      _api.setHttpPusher(
        pushKey: pushKey,
        appId: appId,
        appDisplayName: appDisplayName,
        deviceDisplayName: deviceDisplayName,
        profileTag: profileTag,
        pushGatewayUrl: pushGatewayUrl,
        lang: lang,
      );
}

class MatrixSdkCommunityRepository implements MatrixCommunityRepository {
  MatrixSdkCommunityRepository(this._api);
  final MatrixRepositoryApi _api;

  @override
  Future<XmoInviteLink> generateTrackedInviteLink(String roomId) =>
      _api.generateTrackedInviteLink(roomId);
  @override
  Future<List<XmoInviteLink>> getInviteLinks(String roomId) =>
      _api.getInviteLinks(roomId);
  @override
  Future<void> markRoomAsDirect(String roomId, String otherUserId) =>
      _api.markRoomAsDirect(roomId, otherUserId);
  @override
  Future<void> repairDirectChatMappings() => _api.repairDirectChatMappings();
  @override
  Future<void> revokeInviteLink(String roomId, String linkId) =>
      _api.revokeInviteLink(roomId, linkId);
}
