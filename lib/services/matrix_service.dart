import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton service that wraps the Matrix Dart SDK.
/// Homeserver: http://localhost:8008 (Synapse via Docker)
class MatrixService {
  static final MatrixService _instance = MatrixService._internal();
  factory MatrixService() => _instance;
  MatrixService._internal();

  static const String homeserverUrl = 'http://localhost:8008';
  static const String _authBoxName = 'xmo_auth';

  late Client _client;
  late Box _authBox;

  Client get client => _client;

  bool get isLoggedIn => _client.isLogged();
  String? get userId => _client.userID;
  String? get displayName =>
      _client.userID?.split(':').first.replaceFirst('@', '');

  /// Strips the :server part from a Matrix ID, returning just the username.
  static String cleanName(String matrixId) {
    if (matrixId.contains(':')) {
      return matrixId.split(':').first.replaceFirst('@', '');
    }
    return matrixId.replaceFirst('@', '');
  }

  // ─── Init ────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await Hive.initFlutter();

    // Open credential storage box
    _authBox = await Hive.openBox(_authBoxName);

    _client = Client(
      'XMO',
      databaseBuilder: (_) async {
        if (kIsWeb) {
          final db = HiveCollectionsDatabase('matrix_xmo', '');
          await db.open();
          return db;
        } else {
          final dir = await getApplicationSupportDirectory();
          final db = HiveCollectionsDatabase('matrix_xmo', dir.path);
          await db.open();
          return db;
        }
      },
    );

    await _client.init();
  }

  // ─── Phone-based Auth (primary flow) ─────────────────────────────────────

  /// Derives a stable Matrix username from a phone number.
  String phoneToUsername(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return 'xmo$digits';
  }

  /// Derives a deterministic password from the phone number.
  /// Not security-critical for local dev; use secure storage in production.
  String _phoneToPassword(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final bytes = utf8.encode('xmo_v1_${digits}_synapse_local');
    return base64Url.encode(bytes);
  }

  /// Checks if credentials for [phone] are cached locally.
  bool hasStoredCredentials(String phone) {
    return _authBox.containsKey('phone_$phone');
  }

  /// Logs in or registers a user by phone number.
  /// Call this only after OTP is verified.
  Future<void> loginOrRegisterWithPhone(String phone, String email) async {
    await _client.checkHomeserver(Uri.parse(homeserverUrl));

    final username = phoneToUsername(phone);
    final password = _phoneToPassword(phone);

    if (hasStoredCredentials(phone)) {
      // Returning user — just log in
      try {
        await _client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: username),
          password: password,
        );
        return;
      } catch (_) {
        // Credentials stale? Fall through to register
      }
    }

    // New user — register first, then persist credentials
    try {
      await _client.register(username: username, password: password);
    } on MatrixException catch (e) {
      if (e.errcode == 'M_USER_IN_USE') {
        // Username exists — someone re-installed; just log in
        await _client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: username),
          password: password,
        );
      } else {
        rethrow;
      }
    }

    // Cache credentials so future logins skip registration
    await _authBox.put('phone_$phone', {
      'username': username,
      'password': password,
      'email': email,
    });
  }

  /// Stored email for the current phone number.
  String? getStoredEmail(String phone) {
    final data = _authBox.get('phone_$phone');
    return data?['email'] as String?;
  }

  // ─── Direct login / register (kept for admin use) ─────────────────────────

  Future<void> login(String username, String password) async {
    await _client.checkHomeserver(Uri.parse(homeserverUrl));
    await _client.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: username),
      password: password,
    );
  }

  Future<void> register(String username, String password) async {
    await _client.checkHomeserver(Uri.parse(homeserverUrl));

    // Step 1: Start registration — Synapse returns a UIAA session token
    String? session;
    try {
      await _client.register(username: username, password: password);
      return; // Succeeded without UIAA (unlikely but safe)
    } on MatrixException catch (e) {
      if (e.requireAdditionalAuthentication) {
        // Extract the UIAA session ID from the response
        session = e.raw['session'] as String?;
        if (session == null) rethrow;
      } else if (e.errcode == 'M_USER_IN_USE') {
        // Already exists — just log in instead
        await _client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: username),
          password: password,
        );
        return;
      } else {
        rethrow;
      }
    }

    // Step 2: Complete the m.login.dummy stage with the session token
    try {
      await _client.register(
        username: username,
        password: password,
        auth: AuthenticationData.fromJson({
          'type': 'm.login.dummy',
          'session': session,
        }),
      );
    } on MatrixException catch (e) {
      if (e.errcode == 'M_USER_IN_USE') {
        await _client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: username),
          password: password,
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> logout() async {
    await _client.logout();
  }

  // ─── Rooms ────────────────────────────────────────────────────────────────

  List<Room> getRooms() => _client.rooms;

  /// Get rooms where the user has been invited but hasn't joined yet
  List<Room> getInvitedRooms() {
    return _client.rooms.where((r) => r.membership == Membership.invite).toList();
  }

  /// Auto-accept all pending room invites
  Future<void> acceptAllInvites() async {
    final invites = getInvitedRooms();
    for (final room in invites) {
      try {
        await room.join();
        print('[Matrix] Accepted invite to room: ${room.id}');
      } catch (e) {
        print('[Matrix] Failed to accept invite to ${room.id}: $e');
      }
    }
  }

  Future<String> createRoom({
    required String name,
    String? topic,
    bool isDirect = false,
  }) async {
    return await _client.createRoom(
      name: name,
      topic: topic,
      preset:
          isDirect ? CreateRoomPreset.privateChat : CreateRoomPreset.publicChat,
      isDirect: isDirect,
    );
  }

  Future<String> createDirectRoom(String userId) async {
    return await _client.createRoom(
      invite: [userId],
      preset: CreateRoomPreset.privateChat,
      isDirect: true,
    );
  }

  Future<void> joinRoom(String roomIdOrAlias) async {
    await _client.joinRoom(roomIdOrAlias);
  }

  Room? getRoomById(String roomId) => _client.getRoomById(roomId);

  // ─── Messaging ────────────────────────────────────────────────────────────

  Future<void> sendMessage(String roomId, String message) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    await room.sendTextEvent(message);
  }

  Future<Timeline?> getTimeline(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    return await room.getTimeline();
  }

  // ─── Real-time sync ───────────────────────────────────────────────────────

  Stream<List<Room>> get onRoomsUpdate =>
      _client.onSync.stream.map((_) => _client.rooms);

  Stream<EventUpdate> get onEvent => _client.onEvent.stream;

  void startSync() => _client.sync();

  // ── User search ──────────────────────────────────────────────────────────

  /// Searches for users on the homeserver by display name or user ID.
  Future<List<Profile>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final result = await _client.searchUserDirectory(query, limit: 20);
    return result.results;
  }
}
