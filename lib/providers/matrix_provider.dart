import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:matrix/matrix.dart';
import '../services/matrix_service.dart';

enum MatrixAuthState { uninitialized, loggedOut, loggingIn, loggedIn, error }

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
  final MatrixService _svc = MatrixService();
  MatrixService get service => _svc;

  MatrixAuthState _state = MatrixAuthState.uninitialized;
  MatrixAuthState get state => _state;

  String? _error;
  String? get error => _error;

  bool get isLoggedIn => _state == MatrixAuthState.loggedIn;
  bool get isLoading => _state == MatrixAuthState.loggingIn;
  String? get userId => _svc.userId;
  String? get displayName => _svc.displayName;
  String? get avatarUrl => _svc.avatarUrl;

  List<Room> get rooms => _svc.getRooms();

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      await _svc.init();
      _state = _svc.isLoggedIn
          ? MatrixAuthState.loggedIn
          : MatrixAuthState.loggedOut;
      if (_svc.isLoggedIn) {
        await _svc.refreshProfile();
        _listenSync();
        _svc.startSync();
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
      await _svc.refreshProfile();
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync();
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
      await _svc.refreshProfile();
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync();
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
      await _svc.refreshProfile();
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync();
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
    await _svc.logout();
    _state = MatrixAuthState.loggedOut;
    notifyListeners();
  }

  Future<bool> updateProfile({
    required String displayName,
    Uint8List? avatarBytes,
    String? avatarFileName,
  }) async {
    try {
      _error = null;
      await _svc.updateProfile(
        displayName: displayName,
        avatarBytes: avatarBytes,
        avatarFileName: avatarFileName ?? 'avatar.jpg',
      );
      await _svc.refreshProfile();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ─── Rooms ────────────────────────────────────────────────────────────────

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

  Future<void> sendMessage(String roomId, String text) async {
    await _svc.sendMessage(roomId, text);
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

  Future<String?> startDirectChat(String userId) async {
    try {
      String normalizedUserId = userId.trim();
      if (!normalizedUserId.startsWith('@')) {
        normalizedUserId = '@$normalizedUserId';
      }
      if (!normalizedUserId.contains(':')) {
        normalizedUserId =
            '$normalizedUserId:${MatrixService.matrixServerName}';
      }

      debugPrint(
          '[startDirectChat] Looking for existing DM with $normalizedUserId');
      debugPrint(
          '[startDirectChat] Current rooms count: ${_svc.client.rooms.length}');

      await _svc.client.oneShotSync();
      await _svc.acceptAllInvites();
      await _svc.repairDirectChatMappings();

      final existingDirectRoomId =
          _svc.client.getDirectChatFromUserId(normalizedUserId);
      if (existingDirectRoomId != null) {
        debugPrint(
            '[startDirectChat] Reusing direct room from m.direct: $existingDirectRoomId');
        return existingDirectRoomId;
      }

      for (final room in _svc.client.rooms) {
        debugPrint(
            '[startDirectChat] Checking room ${room.id}: membership=${room.membership}, members=${room.summary.mJoinedMemberCount}');

        if (room.membership != Membership.join &&
            room.membership != Membership.invite) {
          continue;
        }

        final directPeerUserId = _svc.getDirectPeerUserId(room);
        if (directPeerUserId == normalizedUserId) {
          debugPrint(
              '[startDirectChat] Found existing direct room: ${room.id}');

          if (room.membership == Membership.invite) {
            debugPrint('[startDirectChat] Accepting invite to room ${room.id}');
            await room.join();
          }

          await _svc.markRoomAsDirect(room.id, normalizedUserId);
          return room.id;
        }

        if (_svc.looksLikeLegacyDirectRoom(room, normalizedUserId)) {
          debugPrint(
              '[startDirectChat] Repairing legacy direct room: ${room.id}');

          if (room.membership == Membership.invite) {
            debugPrint('[startDirectChat] Accepting invite to room ${room.id}');
            await room.join();
          }

          await _svc.markRoomAsDirect(room.id, normalizedUserId);
          return room.id;
        }
      }

      debugPrint(
          '[startDirectChat] No existing DM found, creating new room with $normalizedUserId');
      final roomId = await _svc.createDirectRoom(normalizedUserId);

      await Future.delayed(const Duration(milliseconds: 500));
      await _svc.client.oneShotSync();
      await _svc.repairDirectChatMappings();

      notifyListeners();
      return roomId;
    } catch (e) {
      debugPrint('[startDirectChat] Error: $e');
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ─── Private ──────────────────────────────────────────────────────────────

  void _listenSync() {
    _svc.onRoomsUpdate.listen((_) async {
      await _svc.acceptAllInvites();
      await _svc.repairDirectChatMappings();
      // Scan every sync cycle: retroactively discover & cache channels
      // whose state events have now arrived (covers joined rooms from other devices)
      _svc.scanAndCacheChannels();
      notifyListeners();
    });
  }

  String _friendlyError(String raw) {
    if (raw.contains('M_FORBIDDEN') || raw.contains('forbidden')) {
      return 'Incorrect credentials. Please try again.';
    }
    if (raw.contains('M_USER_IN_USE')) {
      return 'This number is already registered.';
    }
    if (raw.contains('SocketException') ||
        raw.contains('Connection refused') ||
        raw.contains('Failed host lookup')) {
      return 'Cannot reach server. Is the backend running?';
    }
    return raw.length > 100 ? '${raw.substring(0, 100)}…' : raw;
  }
}
