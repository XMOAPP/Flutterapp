import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../services/call_history_service.dart';
import '../services/matrix_service.dart';
import '../services/privacy_service.dart';
import '../services/push_notification_service.dart';
import '../services/transfer_queue_service.dart';
import '../services/story_upload_queue_service.dart';

enum MatrixAuthState { uninitialized, loggedOut, loggingIn, loggedIn, error }

enum MatrixConnectionStatus { offline, connecting, online, reconnecting }

extension RoomXmoExtension on Room {
  /// Checks if this room is a broadcast channel.
  /// Uses a three-layer check for reliability across hot restarts:
  ///   1. Persistent Hive cache (instant, always available at startup)
  ///   2. Custom xmo.room.type state event (from sync)
  ///   3. Power level fingerprint fallback (events_default >= 50)
  bool get isChannel {
    final svc = MatrixService();

    final kind = MatrixService.classifyRoomKind(
      typeContent: getState(MatrixService.roomTypeStateType)?.content,
      powerLevelsContent: getState('m.room.power_levels')?.content,
      isDirectChat: isDirectChat,
    );
    if (kind == XmoRoomKind.group) {
      svc.cacheGroupId(id);
      return false;
    }
    if (kind == XmoRoomKind.saved) {
      return false;
    }
    if (kind == XmoRoomKind.channel) {
      svc.cacheChannelId(id);
      return true;
    }

    return svc.isKnownChannel(id);
  }

  /// Checks if this room is a group chat.
  /// Uses persistent cache and Matrix state first, with a conservative
  /// non-direct fallback so newly joined groups appear before full state loads.
  bool get isGroup {
    final svc = MatrixService();

    final kind = MatrixService.classifyRoomKind(
      typeContent: getState(MatrixService.roomTypeStateType)?.content,
      powerLevelsContent: getState('m.room.power_levels')?.content,
      isDirectChat: isDirectChat,
    );
    if (kind == XmoRoomKind.group) {
      svc.cacheGroupId(id);
      return true;
    }
    if (kind == XmoRoomKind.saved) {
      return false;
    }
    if (kind == XmoRoomKind.channel) {
      svc.cacheChannelId(id);
      return false;
    }

    if (svc.isKnownChannel(id)) return false;
    if (svc.isKnownGroup(id)) return true;

    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OPTIMIZED MATRIX PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class MatrixProvider extends ChangeNotifier {
  MatrixProvider({MatrixService? service}) : _svc = service ?? MatrixService();

  /// Injectable for integration tests and alternate deployment wiring.
  final MatrixService _svc;
  MatrixService get service => _svc;

  MatrixAuthState _state = MatrixAuthState.uninitialized;
  MatrixAuthState get state => _state;

  String? _error;
  String? get error => _error;

  bool get isLoggedIn => _state == MatrixAuthState.loggedIn;
  bool get isLoading => _state == MatrixAuthState.loggingIn;
  String? get userId => _svc.userId;
  String? get displayName => _optimisticDisplayName ?? _svc.displayName;
  String? get avatarUrl {
    if (_optimisticDisplayName != null &&
        (_optimisticAvatarRemoved || _optimisticAvatarBytes != null)) {
      return null;
    }
    return _svc.avatarUrl;
  }

  Uint8List? get avatarBytes => _optimisticAvatarBytes;

  String? _optimisticDisplayName;
  Uint8List? _optimisticAvatarBytes;
  bool _optimisticAvatarRemoved = false;
  int _profileUpdateVersion = 0;

  MatrixConnectionStatus _connectionStatus = MatrixConnectionStatus.offline;
  MatrixConnectionStatus get connectionStatus => _connectionStatus;
  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;
  int get pendingTransferCount => TransferQueueService.instance.jobs
      .where(
        (job) =>
            job.status == TransferStatus.queued ||
            job.status == TransferStatus.running ||
            job.status == TransferStatus.failed,
      )
      .length;
  StreamSubscription<List<Room>>? _syncSubscription;
  Timer? _connectionWatchdog;
  final Map<String, Future<String?>> _directChatStarts = {};
  final Map<String, DateTime> _directChatRetryAfter = {};

  List<Room> get rooms => _svc.getRooms();

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> init({VoidCallback? beforeStartSync}) async {
    try {
      await _svc.init();
      _state = _svc.isLoggedIn
          ? MatrixAuthState.loggedIn
          : MatrixAuthState.loggedOut;
      await CallHistoryService().setCurrentUser(_svc.userId);
      await TransferQueueService.instance.setCurrentUser(_svc.userId);
      await _setStoryUploadOwner(_svc.userId);
      if (_svc.isLoggedIn) {
        await _svc.refreshProfile();
        await _syncPublicAccountDirectory();
        await _ensureSavedMessagesReady();
        beforeStartSync?.call();
        _listenSync();
        _svc.startSync();
        await PushNotificationService().registerCurrentUser();
      }
    } catch (e) {
      _state = MatrixAuthState.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  // ─── Phone-based login ─────────────────────────────────────────────────────

  Future<bool> loginWithPhone(String phone, String email) async {
    if (_state == MatrixAuthState.loggingIn) {
      return false; // Prevent duplicate calls
    }

    _state = MatrixAuthState.loggingIn;
    _error = null;
    notifyListeners();

    try {
      await _svc.loginOrRegisterWithPhone(phone, email);
      await CallHistoryService().setCurrentUser(_svc.userId);
      await TransferQueueService.instance.setCurrentUser(_svc.userId);
      await _setStoryUploadOwner(_svc.userId);
      await _svc.refreshProfile();
      await _syncPublicAccountDirectory();
      await _ensureSavedMessagesReady();
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync();
      await PushNotificationService().registerCurrentUser();
      notifyListeners();
      return true;
    } catch (e) {
      _state = MatrixAuthState.loggedOut;
      _error = _friendlyError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // ─── Direct auth ───────────────────────────────────────────────────────────

  Future<bool> login(String username, String password) async {
    if (_state == MatrixAuthState.loggingIn) return false;

    _state = MatrixAuthState.loggingIn;
    _error = null;
    notifyListeners();

    try {
      await _svc.login(username, password);
      await CallHistoryService().setCurrentUser(_svc.userId);
      await TransferQueueService.instance.setCurrentUser(_svc.userId);
      await _setStoryUploadOwner(_svc.userId);
      await _svc.refreshProfile();
      await _syncPublicAccountDirectory();
      await _ensureSavedMessagesReady();
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync();
      await PushNotificationService().registerCurrentUser();
      notifyListeners();
      return true;
    } catch (e) {
      _state = MatrixAuthState.loggedOut;
      _error = _friendlyError(e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithSsoToken(String token) async {
    if (_state == MatrixAuthState.loggingIn) return false;

    _state = MatrixAuthState.loggingIn;
    _error = null;
    notifyListeners();

    try {
      await _svc.loginWithSsoToken(token);
      await CallHistoryService().setCurrentUser(_svc.userId);
      await TransferQueueService.instance.setCurrentUser(_svc.userId);
      await _setStoryUploadOwner(_svc.userId);
      await _svc.refreshProfile();
      await _syncPublicAccountDirectory();
      await _ensureSavedMessagesReady();
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync();
      await PushNotificationService().registerCurrentUser();
      notifyListeners();
      return true;
    } catch (e) {
      _state = MatrixAuthState.loggedOut;
      _error = _friendlyError(e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String username, String password) async {
    if (_state == MatrixAuthState.loggingIn) return false;

    _state = MatrixAuthState.loggingIn;
    _error = null;
    notifyListeners();

    try {
      await _svc.register(username, password);
      if ((_svc.accessToken ?? '').isEmpty) {
        await _svc.login(username, password);
      }
      await CallHistoryService().setCurrentUser(_svc.userId);
      await TransferQueueService.instance.setCurrentUser(_svc.userId);
      await _setStoryUploadOwner(_svc.userId);
      await _svc.refreshProfile();
      await _syncPublicAccountDirectory();
      await _ensureSavedMessagesReady();
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync();
      await PushNotificationService().registerCurrentUser();
      notifyListeners();
      return true;
    } catch (e) {
      _state = MatrixAuthState.loggedOut;
      _error = _friendlyError(e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await PushNotificationService().unregisterCurrentUser();
    await _svc.logout();
    await CallHistoryService().setCurrentUser(null);
    await TransferQueueService.instance.setCurrentUser(null);
    await _setStoryUploadOwner(null);
    _state = MatrixAuthState.loggedOut;
    _connectionStatus = MatrixConnectionStatus.offline;
    notifyListeners();
  }

  Future<bool> deleteAccount({String? password, bool erase = true}) async {
    if (_state != MatrixAuthState.loggedIn) return false;

    _error = null;
    notifyListeners();

    try {
      try {
        await PushNotificationService().unregisterCurrentUser();
      } catch (_) {
        // Account deletion must still be allowed if push cleanup is offline.
      }
      await _syncSubscription?.cancel();
      _syncSubscription = null;
      _connectionWatchdog?.cancel();
      _connectionWatchdog = null;
      await _svc.deactivateAccount(password: password, erase: erase);
      await CallHistoryService().setCurrentUser(null);
      await TransferQueueService.instance.setCurrentUser(null);
      await _discardStoryUploads();
      await _setStoryUploadOwner(null);
      _state = MatrixAuthState.loggedOut;
      _connectionStatus = MatrixConnectionStatus.offline;
      _lastSyncAt = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _friendlyError(e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfile({
    required String displayName,
    Uint8List? avatarBytes,
    String? avatarFileName,
    bool removeAvatar = false,
  }) async {
    final cleanDisplayName = displayName.trim();
    if (cleanDisplayName.isEmpty) {
      _error = 'Display name cannot be empty';
      notifyListeners();
      return false;
    }

    final updateVersion = ++_profileUpdateVersion;
    _error = null;
    _optimisticDisplayName = cleanDisplayName;
    _optimisticAvatarBytes = removeAvatar ? null : avatarBytes;
    _optimisticAvatarRemoved = removeAvatar;
    notifyListeners();

    try {
      await _svc.updateProfile(
        displayName: cleanDisplayName,
        avatarBytes: avatarBytes,
        avatarFileName: avatarFileName ?? 'avatar.jpg',
        removeAvatar: removeAvatar,
      );
      if (updateVersion == _profileUpdateVersion) {
        _clearOptimisticProfile();
        notifyListeners();
      }
      unawaited(
        _syncPublicAccountDirectory().catchError((Object error) {
          debugPrint(
            '[MatrixProvider] Profile directory sync deferred: $error',
          );
        }),
      );
      return true;
    } catch (e) {
      _error = e.toString();
      if (updateVersion == _profileUpdateVersion) {
        _clearOptimisticProfile();
        notifyListeners();
      }
      return false;
    }
  }

  void _clearOptimisticProfile() {
    _optimisticDisplayName = null;
    _optimisticAvatarBytes = null;
    _optimisticAvatarRemoved = false;
  }

  Future<void> _syncPublicAccountDirectory() async {
    final privacyService = PrivacyService(_svc);
    final privacySettings = await privacyService.loadSettings();
    if (privacySettings.accountIsPublic) {
      await privacyService.syncPublicAccountDirectory(privacySettings);
    }
  }

  // ─── Rooms ────────────────────────────────────────────────────────────────

  Future<void> _ensureSavedMessagesReady() async {
    try {
      await _svc.getOrCreateSavedMessagesRoom();
      await _svc.deleteDuplicateSavedMessagesRooms();
    } catch (e) {
      debugPrint('[MatrixProvider] Saved Messages startup skipped: $e');
    }
  }

  Future<String?> createRoom(String name, {bool isDirect = false}) async {
    try {
      final id = await _svc.createRoom(name: name, isDirect: isDirect);
      notifyListeners();
      return id;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> sendMessage(
    String roomId,
    String text, {
    Map<String, dynamic> extraContent = const {},
  }) async {
    await _svc.sendMessage(roomId, text, extraContent: extraContent);
  }

  Future<Room> getOrCreateSavedMessagesRoom() async {
    final room = await _svc.getOrCreateSavedMessagesRoom();
    notifyListeners();
    return room;
  }

  Future<int> deleteDuplicateSavedMessagesRooms() async {
    final count = await _svc.deleteDuplicateSavedMessagesRooms();
    if (count > 0) notifyListeners();
    return count;
  }

  void refreshRooms() {
    _svc.scanAndCacheChannels();
    notifyListeners();
  }

  Future<List<Profile>> searchUsers(String query) async {
    try {
      return await _svc.searchUsers(query);
    } catch (e) {
      _error = e.toString();
      return [];
    }
  }

  String normalizeUserId(String userId) {
    var normalizedUserId = userId.trim();
    if (!normalizedUserId.startsWith('@')) {
      normalizedUserId = '@$normalizedUserId';
    }
    if (!normalizedUserId.contains(':')) {
      normalizedUserId = '$normalizedUserId:${MatrixService.matrixServerName}';
    }
    return normalizedUserId;
  }

  Room? findExistingDirectRoom(String userId) {
    final normalizedUserId = normalizeUserId(userId);
    final mappedRoomId = _svc.client.getDirectChatFromUserId(normalizedUserId);
    if (mappedRoomId != null) {
      final room = _svc.getRoomById(mappedRoomId);
      if (room != null && room.membership == Membership.join) return room;
    }

    for (final room in _svc.client.rooms) {
      if (room.membership != Membership.join) continue;
      final directPeerUserId = _svc.getDirectPeerUserId(room);
      if (directPeerUserId == normalizedUserId ||
          _svc.looksLikeLegacyDirectRoom(room, normalizedUserId)) {
        return room;
      }
    }
    return null;
  }

  Future<String?> startDirectChat(String userId) async {
    final normalizedUserId = normalizeUserId(userId);
    final retryAfter = _directChatRetryAfter[normalizedUserId];
    if (retryAfter != null && retryAfter.isAfter(DateTime.now())) {
      final seconds = retryAfter.difference(DateTime.now()).inSeconds + 1;
      _error = 'Too many requests. Try again in $seconds seconds.';
      notifyListeners();
      return null;
    }
    _directChatRetryAfter.remove(normalizedUserId);

    final pending = _directChatStarts[normalizedUserId];
    if (pending != null) return pending;

    final operation = _startDirectChatOnce(normalizedUserId);
    _directChatStarts[normalizedUserId] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_directChatStarts[normalizedUserId], operation)) {
        _directChatStarts.remove(normalizedUserId);
      }
    }
  }

  Future<String?> _startDirectChatOnce(String normalizedUserId) async {
    try {
      debugPrint(
        '[startDirectChat] Looking for existing DM with $normalizedUserId',
      );
      debugPrint(
        '[startDirectChat] Current rooms count: ${_svc.client.rooms.length}',
      );

      final cachedRoom = findExistingDirectRoom(normalizedUserId);
      if (cachedRoom != null) {
        debugPrint(
          '[startDirectChat] Reusing cached direct room: ${cachedRoom.id}',
        );
        return cachedRoom.id;
      }

      final existingDirectRoomId = _svc.client.getDirectChatFromUserId(
        normalizedUserId,
      );
      if (existingDirectRoomId != null) {
        debugPrint(
          '[startDirectChat] Reusing direct room from m.direct: $existingDirectRoomId',
        );
        return existingDirectRoomId;
      }

      for (final room in _svc.client.rooms) {
        debugPrint(
          '[startDirectChat] Checking room ${room.id}: membership=${room.membership}, members=${room.summary.mJoinedMemberCount}',
        );

        if (room.membership != Membership.join &&
            room.membership != Membership.invite) {
          continue;
        }

        final directPeerUserId = _svc.getDirectPeerUserId(room);
        if (directPeerUserId == normalizedUserId) {
          debugPrint(
            '[startDirectChat] Found existing direct room: ${room.id}',
          );

          if (room.membership == Membership.invite) {
            debugPrint('[startDirectChat] Accepting invite to room ${room.id}');
            await room.join();
          }

          await _svc.markRoomAsDirect(room.id, normalizedUserId);
          return room.id;
        }

        if (_svc.looksLikeLegacyDirectRoom(room, normalizedUserId)) {
          debugPrint(
            '[startDirectChat] Repairing legacy direct room: ${room.id}',
          );

          if (room.membership == Membership.invite) {
            debugPrint('[startDirectChat] Accepting invite to room ${room.id}');
            await room.join();
          }

          await _svc.markRoomAsDirect(room.id, normalizedUserId);
          return room.id;
        }
      }

      debugPrint(
        '[startDirectChat] No existing DM found, creating new room with $normalizedUserId',
      );
      final roomId = await _svc.createDirectRoom(normalizedUserId);
      notifyListeners();
      return roomId;
    } catch (e) {
      debugPrint('[startDirectChat] Error: $e');
      if (e is MatrixException && e.error == MatrixError.M_LIMIT_EXCEEDED) {
        final delay = Duration(milliseconds: e.retryAfterMs ?? 5000);
        _directChatRetryAfter[normalizedUserId] = DateTime.now().add(delay);
      }
      _error = _directChatError(e);
      notifyListeners();
      return null;
    }
  }

  String _directChatError(Object error) {
    if (error is MatrixException &&
        error.error == MatrixError.M_LIMIT_EXCEEDED) {
      final retryAfterMs = error.retryAfterMs;
      if (retryAfterMs != null && retryAfterMs > 0) {
        final seconds = (retryAfterMs / 1000).ceil();
        return 'Too many requests. Try again in $seconds seconds.';
      }
      return 'Too many requests. Please wait and try again.';
    }
    return _friendlyError(error.toString());
  }

  // ─── Private ──────────────────────────────────────────────────────────────

  Future<void> _setStoryUploadOwner(String? userId) async {
    try {
      await StoryUploadQueueService.instance.setCurrentUser(userId);
    } catch (error) {
      debugPrint('[MatrixProvider] Story upload queue unavailable: $error');
    }
  }

  Future<void> _discardStoryUploads() async {
    try {
      await StoryUploadQueueService.instance.discardCurrentUserJobs();
    } catch (error) {
      debugPrint('[MatrixProvider] Failed to discard Story uploads: $error');
    }
  }

  void _listenSync() {
    _syncSubscription?.cancel();
    _connectionWatchdog ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkConnectionHealth(),
    );
    _connectionStatus = MatrixConnectionStatus.connecting;
    _syncSubscription = _svc.onRoomsUpdate.listen((_) async {
      _lastSyncAt = DateTime.now();
      if (_connectionStatus != MatrixConnectionStatus.online) {
        _connectionStatus = MatrixConnectionStatus.online;
      }
      await _svc.acceptAllInvites();
      await _svc.repairDirectChatMappings();
      // Scan every sync cycle: retroactively discover & cache channels
      // whose state events have now arrived (covers joined rooms from other devices)
      _svc.scanAndCacheChannels();
      notifyListeners();
    });
  }

  void _checkConnectionHealth() {
    if (!isLoggedIn) return;
    final lastSyncAt = _lastSyncAt;
    if (lastSyncAt == null ||
        DateTime.now().difference(lastSyncAt) > const Duration(seconds: 45)) {
      if (_connectionStatus != MatrixConnectionStatus.reconnecting) {
        _connectionStatus = MatrixConnectionStatus.reconnecting;
        notifyListeners();
      }
    }
  }

  Future<void> retryConnection() async {
    if (!isLoggedIn) return;
    _connectionStatus = MatrixConnectionStatus.connecting;
    notifyListeners();
    try {
      await _svc.client.oneShotSync();
      _svc.startSync();
      _lastSyncAt = DateTime.now();
      _connectionStatus = MatrixConnectionStatus.online;
    } catch (e) {
      _connectionStatus = MatrixConnectionStatus.offline;
      _error = _friendlyError(e.toString());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _connectionWatchdog?.cancel();
    super.dispose();
  }

  String _friendlyError(String raw) {
    if (raw.contains('M_FORBIDDEN') || raw.contains('forbidden')) {
      return 'Invalid username/password. Please try again.';
    }
    if (raw.contains('M_USER_IN_USE')) {
      return 'Username already taken.';
    }
    if (raw.contains('SocketException') ||
        raw.contains('Connection refused') ||
        raw.contains('Failed host lookup')) {
      return 'Cannot reach server. Is the backend running?';
    }
    return raw.length > 100 ? '${raw.substring(0, 100)}…' : raw;
  }
}
