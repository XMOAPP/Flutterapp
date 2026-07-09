import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import '../../models/invite_link_models.dart';

/// Small testable contracts for Matrix responsibilities. UI and feature code
/// can depend on these instead of a concrete SDK-backed service.
abstract interface class MatrixSessionRepository {
  bool get isLoggedIn;
  String? get userId;
  String? get displayName;
  String? get avatarUrl;

  Future<void> init();
  Future<void> login(String username, String password);
  Future<void> register(String username, String password);
  Future<void> logout();
  Future<void> refreshProfile();
  Future<void> updateProfile({
    required String displayName,
    Uint8List? avatarBytes,
    String avatarFileName,
    bool removeAvatar,
  });
}

abstract interface class MatrixRoomRepository {
  List<Room> getRooms();
  Future<String> createRoom({
    required String name,
    String? topic,
    bool isDirect,
  });
  Future<String> createDirectRoom(String userId);
  Future<String> createChannel({
    required String name,
    String? topic,
    bool isPublic,
  });
  Future<void> joinRoom(String roomIdOrAlias);
  Future<Timeline?> getTimeline(String roomId);
}

abstract interface class MatrixMediaRepository {
  Future<void> sendMessage(String roomId, String message);
  Future<void> sendFileWithProgress({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
    Map<String, dynamic>? xmoStream,
  });
  Future<void> sendImageWithCaption({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String caption,
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
    Map<String, dynamic>? xmoStream,
  });
}

abstract interface class MatrixPushRepository {
  Future<void> setHttpPusher({
    required String pushKey,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    required String profileTag,
    required String pushGatewayUrl,
    String lang,
  });
  Future<void> removeHttpPusher({
    required String pushKey,
    required String appId,
  });
}

abstract interface class MatrixCommunityRepository {
  Future<XmoInviteLink> generateTrackedInviteLink(String roomId);
  Future<List<XmoInviteLink>> getInviteLinks(String roomId);
  Future<void> revokeInviteLink(String roomId, String linkId);
  Future<void> markRoomAsDirect(String roomId, String otherUserId);
  Future<void> repairDirectChatMappings();
}

/// Internal façade implemented by MatrixService. Keeping this small lets the
/// repository adapters remain testable with fake implementations.
abstract interface class MatrixRepositoryApi
    implements
        MatrixSessionRepository,
        MatrixRoomRepository,
        MatrixMediaRepository,
        MatrixPushRepository,
        MatrixCommunityRepository {}
