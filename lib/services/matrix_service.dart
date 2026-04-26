import 'dart:async';
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

  late Client _client;
  Client get client => _client;

  bool get isLoggedIn => _client.isLogged();
  String? get userId => _client.userID;
  String? get displayName => _client.userID?.split(':').first.replaceFirst('@', '');

  // ─── Init ────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await Hive.initFlutter();

    _client = Client(
      'XMO',
      databaseBuilder: (_) async {
        if (kIsWeb) {
          // Web: HiveCollectionsDatabase uses IndexedDB, no file path needed
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

  // ─── Auth ─────────────────────────────────────────────────────────────────

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
    try {
      await _client.register(
        username: username,
        password: password,
      );
    } on MatrixException catch (e) {
      // UIA flow — handle interactive auth if needed
      if (e.requireAdditionalAuthentication) rethrow;
      rethrow;
    }
  }

  Future<void> logout() async {
    await _client.logout();
  }

  // ─── Rooms ────────────────────────────────────────────────────────────────

  List<Room> getRooms() => _client.rooms;

  Future<String> createRoom({
    required String name,
    String? topic,
    bool isDirect = false,
  }) async {
    return await _client.createRoom(
      name: name,
      topic: topic,
      preset: isDirect ? CreateRoomPreset.privateChat : CreateRoomPreset.publicChat,
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

  Stream<List<Room>> get onRoomsUpdate => _client.onSync.stream.map((_) => _client.rooms);

  Stream<EventUpdate> get onEvent => _client.onEvent.stream;

  void startSync() => _client.sync();
}
