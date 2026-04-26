import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../services/matrix_service.dart';

enum MatrixAuthState { uninitialized, loggedOut, loggingIn, loggedIn, error }

/// ChangeNotifier wrapping MatrixService.
/// Drives auth state, phone-based OTP login, and room list.
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

  List<Room> get rooms => _svc.getRooms();

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      await _svc.init();
      _state =
          _svc.isLoggedIn ? MatrixAuthState.loggedIn : MatrixAuthState.loggedOut;
      if (_svc.isLoggedIn) {
        _listenSync();
        // Start syncing immediately to receive messages
        _svc.startSync();
      }
    } catch (e) {
      _state = MatrixAuthState.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  // ─── Phone-based login (primary flow) ─────────────────────────────────────

  /// Call after OTP is verified. Registers or logs in via Matrix silently.
  Future<bool> loginWithPhone(String phone, String email) async {
    _state = MatrixAuthState.loggingIn;
    _error = null;
    notifyListeners();
    try {
      await _svc.loginOrRegisterWithPhone(phone, email);
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync(); // Start syncing to receive messages
      notifyListeners();
      return true;
    } catch (e) {
      _state = MatrixAuthState.loggedOut;
      _error = _friendlyError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // ─── Direct auth (kept for admin/testing) ─────────────────────────────────

  Future<bool> login(String username, String password) async {
    _state = MatrixAuthState.loggingIn;
    _error = null;
    notifyListeners();
    try {
      await _svc.login(username, password);
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync(); // Start syncing to receive messages
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
    _state = MatrixAuthState.loggingIn;
    _error = null;
    notifyListeners();
    try {
      await _svc.register(username, password);
      _state = MatrixAuthState.loggedIn;
      _listenSync();
      _svc.startSync(); // Start syncing to receive messages
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

  /// Searches the Matrix user directory for users matching [query].
  Future<List<Profile>> searchUsers(String query) async {
    try {
      return await _svc.searchUsers(query);
    } catch (e) {
      _error = e.toString();
      return [];
    }
  }

  /// Creates or retrieves a direct chat room with [userId] and returns its ID.
  Future<String?> startDirectChat(String userId) async {
    try {
      // Normalize the user ID
      String normalizedUserId = userId.trim();
      if (!normalizedUserId.startsWith('@')) {
        normalizedUserId = '@$normalizedUserId';
      }
      if (!normalizedUserId.contains(':')) {
        normalizedUserId = '$normalizedUserId:localhost';
      }

      print('[startDirectChat] Looking for existing DM with $normalizedUserId');
      print('[startDirectChat] Current rooms count: ${_svc.client.rooms.length}');

      // Force a sync to get latest room list
      await _svc.client.oneShotSync();
      
      // Auto-accept any pending invites first
      await _svc.acceptAllInvites();
      
      // Check all existing rooms (including invited ones) for a DM with this user
      for (final room in _svc.client.rooms) {
        print('[startDirectChat] Checking room ${room.id}: membership=${room.membership}, members=${room.summary.mJoinedMemberCount}');
        
        // Skip if we're not in the room (banned, left, etc.)
        if (room.membership != Membership.join && room.membership != Membership.invite) {
          continue;
        }
        
        // Get all participant IDs (including invited users)
        final participantIds = <String>[];
        for (final user in room.getParticipants()) {
          participantIds.add(user.id);
        }
        
        // Also check invited users
        final states = room.states[EventTypes.RoomMember];
        if (states != null) {
          for (final state in states.values) {
            final membership = state.content['membership'];
            if (membership == 'invite' || membership == 'join') {
              final stateKey = state.stateKey;
              if (stateKey != null && !participantIds.contains(stateKey)) {
                participantIds.add(stateKey);
              }
            }
          }
        }
        
        print('[startDirectChat] All participants (including invites): $participantIds');
        
        // Check if this room has the target user
        if (participantIds.contains(normalizedUserId)) {
          print('[startDirectChat] ✅ Found existing room: ${room.id}');
          
          // If it's an invite, accept it
          if (room.membership == Membership.invite) {
            print('[startDirectChat] Accepting invite to room ${room.id}');
            await room.join();
          }
          
          return room.id;
        }
      }
      
      print('[startDirectChat] ❌ No existing DM found, creating new room with $normalizedUserId');
      // No existing DM — create one
      final roomId = await _svc.createDirectRoom(normalizedUserId);
      
      // Wait a bit for the room to sync
      await Future.delayed(const Duration(milliseconds: 500));
      await _svc.client.oneShotSync();
      
      notifyListeners();
      return roomId;
    } catch (e) {
      print('[startDirectChat] ❌ Error: $e');
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ─── Private ──────────────────────────────────────────────────────────────

  void _listenSync() {
    _svc.onRoomsUpdate.listen((_) {
      // Auto-accept any pending invites
      _svc.acceptAllInvites();
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
