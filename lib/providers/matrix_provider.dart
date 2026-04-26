import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../services/matrix_service.dart';

enum MatrixAuthState { uninitialized, loggedOut, loggingIn, loggedIn, error }

/// ChangeNotifier wrapping MatrixService — drives login state and room list.
class MatrixProvider extends ChangeNotifier {
  final MatrixService _svc = MatrixService();
  MatrixService get service => _svc;

  MatrixAuthState _state = MatrixAuthState.uninitialized;
  MatrixAuthState get state => _state;

  String? _error;
  String? get error => _error;

  bool get isLoggedIn => _state == MatrixAuthState.loggedIn;
  String? get userId => _svc.userId;
  String? get displayName => _svc.displayName;

  List<Room> get rooms => _svc.getRooms();

  // ─── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      await _svc.init();
      _state = _svc.isLoggedIn ? MatrixAuthState.loggedIn : MatrixAuthState.loggedOut;
      if (_svc.isLoggedIn) _listenSync();
    } catch (e) {
      _state = MatrixAuthState.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  // ─── Login / Register ──────────────────────────────────────────────────────

  Future<bool> login(String username, String password) async {
    _state = MatrixAuthState.loggingIn;
    _error = null;
    notifyListeners();
    try {
      await _svc.login(username, password);
      _state = MatrixAuthState.loggedIn;
      _listenSync();
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

  // ─── Rooms ─────────────────────────────────────────────────────────────────

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

  // ─── Private ───────────────────────────────────────────────────────────────

  void _listenSync() {
    _svc.onRoomsUpdate.listen((_) => notifyListeners());
  }

  String _friendlyError(String raw) {
    if (raw.contains('M_FORBIDDEN') || raw.contains('forbidden')) {
      return 'Wrong username or password.';
    }
    if (raw.contains('M_USER_IN_USE')) {
      return 'Username already taken. Try another.';
    }
    if (raw.contains('SocketException') || raw.contains('Connection refused')) {
      return 'Cannot reach server. Is Docker running?';
    }
    return raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
  }
}
