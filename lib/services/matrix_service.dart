// ignore_for_file: annotate_overrides

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/invite_link_models.dart';
import 'azure_blob_chunk_storage_service.dart';
import 'matrix_encrypted_media_helper.dart';
import 'matrix_media_helper.dart';
import 'repositories/matrix_repository_contracts.dart';
import 'repositories/matrix_sdk_repositories.dart';
import 'room_controls_service.dart';
import 'transfer_queue_service.dart';
import 'video_quality_variant_provider_stub.dart'
    if (dart.library.io) 'video_quality_variant_provider_io.dart';
import 'xmo_chunked_media_upload_service.dart';
import 'xmo_media_compatibility.dart';

enum XmoRoomKind { direct, group, channel, saved }

class MatrixUploadCancelledException implements Exception {
  const MatrixUploadCancelledException();

  @override
  String toString() => 'Upload cancelled';
}

class MatrixAccountDeactivationException implements Exception {
  const MatrixAccountDeactivationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PreparedMediaUpload {
  final Uint8List bytes;
  final String contentType;
  final EncryptedFile? encryptedFile;

  const _PreparedMediaUpload({
    required this.bytes,
    required this.contentType,
    this.encryptedFile,
  });
}

/// Singleton service that wraps the Matrix Dart SDK.
/// Matrix homeserver wrapper. Configure deployment with --dart-define.
class MatrixService implements MatrixRepositoryApi {
  static final MatrixService _instance = MatrixService._internal();
  factory MatrixService() => _instance;
  MatrixService._internal();

  static const String homeserverUrl = AppConfig.homeserverUrl;
  static const String matrixServerName = AppConfig.matrixServerName;
  static const String _authBoxName = 'xmo_auth';
  static const String _channelBoxName = 'xmo_channels';
  static const String _groupBoxName = 'xmo_groups';
  static const String _savedMessagesRoomIdKey = 'saved_messages_room_id';
  static const String _inviteLinksStateType = 'xmo.invite.links';
  static const String roomTypeStateType = 'xmo.room.type';
  static const String roomSecurityStateType = 'xmo.room.security';
  static const String savedMessagesStateType = 'xmo.saved_messages';
  static const String groupCallPushMarkerEvent = 'xmo.group_call_invite';

  late Client _client;
  late Box _authBox;
  late Box _channelBox;
  late Box _groupBox;
  final MatrixEncryptedMediaHelper _encryptedMediaHelper =
      const MatrixEncryptedMediaHelper();
  late final XmoChunkedMediaUploadService _chunkedMediaUploadService =
      XmoChunkedMediaUploadService(
    qualityVariantProvider: createVideoCompressionQualityVariantProvider(),
    sourceNormalizer: createVideoCompressionSourceNormalizer(),
  );
  AzureBlobChunkStorageService? _azureBlobChunkStorageService;
  final Set<String> _channelIdCache = {};
  final Set<String> _groupIdCache = {};
  final Set<String> _publishedRoomIds = {};
  String? _savedMessagesRoomId;
  bool _hasPublishedExisting = false;
  String? _profileDisplayName;
  String? _profileAvatarUrl;
  bool _profileAvatarRemoved = false;

  /// Repository boundaries retain the existing MatrixService API while making
  /// feature code unit-testable with repository fakes.
  late final MatrixSessionRepository sessionRepository =
      MatrixSdkSessionRepository(this);
  late final MatrixRoomRepository roomRepository =
      MatrixSdkRoomRepository(this);
  late final MatrixMediaRepository mediaRepository =
      MatrixSdkMediaRepository(this);
  late final MatrixPushRepository pushRepository =
      MatrixSdkPushRepository(this);
  late final MatrixCommunityRepository communityRepository =
      MatrixSdkCommunityRepository(this);

  Client get client => _client;

  bool get isLoggedIn => _client.isLogged();
  String? get userId => _client.userID;
  String? get currentLoginUsername =>
      _client.userID?.split(':').first.replaceFirst('@', '');
  bool get hasCachedPasswordForCurrentUser =>
      _storedPasswordForCurrentUser() != null;
  String? get displayName => _profileDisplayName?.trim().isNotEmpty == true
      ? _profileDisplayName
      : _client.userID?.split(':').first.replaceFirst('@', '');

  static bool isGroupCallPushMarkerContent(Map? content) {
    if (content == null) return false;
    final xmoEvent = content['xmo_event']?.toString();
    final pushType = content['xmo_push_type']?.toString();
    final callKind = content['xmo_call_kind']?.toString();
    final groupCall = content['group_call'];
    return xmoEvent == groupCallPushMarkerEvent ||
        (pushType == 'call' && callKind == 'group') ||
        groupCall == true ||
        groupCall?.toString().toLowerCase() == 'true';
  }

  static bool isGroupCallPushMarker(Event event) {
    return event.type == EventTypes.Message &&
        isGroupCallPushMarkerContent(event.content);
  }

  String? get avatarUrl {
    if (_profileAvatarRemoved) return null;
    if (_profileAvatarUrl?.trim().isNotEmpty == true) {
      return _profileAvatarUrl;
    }
    final userId = _client.userID;
    if (userId == null) return null;
    return _client.rooms
        .map((room) =>
            room.getState(EventTypes.RoomMember, userId)?.asUser.avatarUrl)
        .firstWhere(
          (avatar) => avatar != null,
          orElse: () => null,
        )
        ?.toString();
  }

  Future<void> refreshProfile() async {
    final userId = _client.userID;
    if (userId == null) return;

    try {
      final profile = await _client.getProfileFromUserId(userId);
      _profileDisplayName = profile.displayName;
      _profileAvatarUrl = profile.avatarUrl?.toString();
      _profileAvatarRemoved = _profileAvatarUrl?.trim().isNotEmpty != true;
    } catch (e) {
      debugPrint('[MatrixService] Failed to refresh profile: $e');
    }
  }

  Future<void> updateProfile({
    required String displayName,
    Uint8List? avatarBytes,
    String avatarFileName = 'avatar.jpg',
    bool removeAvatar = false,
  }) async {
    final userId = _client.userID;
    if (userId == null) throw Exception('User not logged in');

    final cleanDisplayName = displayName.trim();
    if (cleanDisplayName.isEmpty) {
      throw Exception('Display name cannot be empty');
    }

    await _client.setDisplayName(userId, cleanDisplayName);
    _profileDisplayName = cleanDisplayName;

    if (removeAvatar) {
      await _client.setAvatarUrl(userId, Uri.parse(''));
      _profileAvatarUrl = null;
      _profileAvatarRemoved = true;
    } else if (avatarBytes != null && avatarBytes.isNotEmpty) {
      final avatarMxc = await _client.uploadContent(
        avatarBytes,
        filename: avatarFileName,
        contentType: _imageContentTypeForName(avatarFileName),
      );
      await _client.setAvatarUrl(userId, avatarMxc);
      _profileAvatarUrl = avatarMxc.toString();
      _profileAvatarRemoved = false;
    }
  }

  String _imageContentTypeForName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  /// Strips the :server part from a Matrix ID, returning just the username.
  static String cleanName(String matrixId) {
    if (matrixId.contains(':')) {
      return matrixId.split(':').first.replaceFirst('@', '');
    }
    return matrixId.replaceFirst('@', '');
  }

  /// Builds a Matrix invite URL that can be copied, shared, or encoded as QR.
  static String buildMatrixToLink(String roomIdOrAlias) {
    return 'https://matrix.to/#/${Uri.encodeComponent(roomIdOrAlias)}';
  }

  /// Extracts a room ID or alias from supported invite/search formats.
  /// Accepts matrix.to links, raw room IDs (!room:server), and aliases (#name:server).
  static String? extractRoomIdentifier(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('!') || value.startsWith('#')) return value;

    final uri = Uri.tryParse(value);
    if (uri == null) return null;

    if (uri.host == 'matrix.to') {
      final fragment = uri.fragment;
      if (fragment.isEmpty) return null;
      final rawIdentifier =
          fragment.startsWith('/') ? fragment.substring(1) : fragment;
      final decodedIdentifier = Uri.decodeComponent(rawIdentifier);
      final identifier = decodedIdentifier.split('?').first;
      if (identifier.startsWith('!') || identifier.startsWith('#')) {
        return identifier;
      }
    }

    return null;
  }

  /// Classifies an XMO room from Matrix state content.
  /// Explicit xmo.room.type state wins over power-level heuristics.
  static XmoRoomKind? classifyRoomKind({
    Map<dynamic, dynamic>? typeContent,
    Map<dynamic, dynamic>? powerLevelsContent,
    required bool isDirectChat,
    bool useGroupFallback = false,
  }) {
    if (typeContent?['is_direct'] == true || typeContent?['kind'] == 'direct') {
      return XmoRoomKind.direct;
    }
    if (typeContent?['is_saved_messages'] == true ||
        typeContent?['kind'] == 'saved') {
      return XmoRoomKind.saved;
    }
    if (typeContent?['is_channel'] == true) return XmoRoomKind.channel;
    if (typeContent?['is_group'] == true) return XmoRoomKind.group;

    if (powerLevelsMarkChannel(powerLevelsContent)) {
      return XmoRoomKind.channel;
    }

    if (isDirectChat) return XmoRoomKind.direct;
    if (useGroupFallback) return XmoRoomKind.group;
    return null;
  }

  /// Broadcast channels require elevated default message power.
  static bool powerLevelsMarkChannel(Map<dynamic, dynamic>? content) {
    final eventsDefault = content?['events_default'];
    final usersDefault = content?['users_default'];
    return eventsDefault is num &&
        eventsDefault.toInt() >= 50 &&
        (usersDefault == null ||
            (usersDefault is num && usersDefault.toInt() == 0));
  }

  // ─── Init ────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await Hive.initFlutter();

    // Open credential storage box
    _authBox = await Hive.openBox(_authBoxName);
    _savedMessagesRoomId = _authBox.get(_savedMessagesRoomIdKey) as String?;

    // Open channel ID cache (survives restarts — instant channel detection)
    _channelBox = await Hive.openBox(_channelBoxName);
    _loadChannelCache();

    _groupBox = await Hive.openBox(_groupBoxName);
    _loadGroupCache();

    // Open persistent media cache box for thumbnails
    await Hive.openBox<Uint8List>('xmo_media_cache');
    await Hive.openBox('xmo_app_settings');
    await Hive.openBox('xmo_call_history');
    await Hive.openBox('xmo_shared_media_index');
    await Hive.openBox(TransferQueueService.boxName);
    await TransferQueueService.instance.init();

    _client = Client(
      'XMO',
      verificationMethods: {
        KeyVerificationMethod.numbers,
        KeyVerificationMethod.emoji,
      },
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

  Future<bool> isUsernameAvailable(String username) async {
    await _client.checkHomeserver(Uri.parse(homeserverUrl));
    return await _client.checkUsernameAvailability(username) == true;
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
        rethrow;
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
        rethrow;
      } else {
        rethrow;
      }
    }
  }

  Future<void> logout() async {
    await _client.logout();
  }

  Future<void> deactivateAccount({
    String? password,
    bool erase = true,
  }) async {
    final token = accessToken;
    final loginUser = currentLoginUsername;
    final authPassword = password?.trim().isNotEmpty == true
        ? password!.trim()
        : _storedPasswordForCurrentUser();

    if (token == null || token.isEmpty || loginUser == null) {
      throw const MatrixAccountDeactivationException(
        'You must be logged in to delete this account.',
      );
    }
    if (authPassword == null || authPassword.isEmpty) {
      throw const MatrixAccountDeactivationException(
        'Enter your account password to delete this account.',
      );
    }

    final session = await _sendDeactivateAccountRequest(
      token: token,
      erase: erase,
      authUser: loginUser,
      password: authPassword,
    );

    if (session != null) {
      await _sendDeactivateAccountRequest(
        token: token,
        erase: erase,
        authUser: loginUser,
        password: authPassword,
        session: session,
      );
    }

    await _removeStoredCredentialsForCurrentUser();
    await _client.clear();
  }

  Future<String?> _sendDeactivateAccountRequest({
    required String token,
    required bool erase,
    required String authUser,
    required String password,
    String? session,
  }) async {
    final uri =
        Uri.parse('$homeserverUrl/_matrix/client/v3/account/deactivate');
    final httpClient = io.HttpClient();
    try {
      final request = await httpClient.postUrl(uri);
      request.headers
        ..set(io.HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(io.HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode({
        'erase': erase,
        'auth': {
          'type': 'm.login.password',
          'identifier': {
            'type': 'm.id.user',
            'user': authUser,
          },
          'password': password,
          if (session != null) 'session': session,
        },
      }));

      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      final responseBody = await utf8.decodeStream(response);
      final decoded = responseBody.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }

      if (response.statusCode == 401 && session == null) {
        final nextSession = decoded['session'];
        if (nextSession is String && nextSession.isNotEmpty) {
          return nextSession;
        }
      }

      final message = decoded['error'] as String?;
      throw MatrixAccountDeactivationException(
        message?.isNotEmpty == true
            ? message!
            : 'Failed to delete account (${response.statusCode}).',
      );
    } on MatrixAccountDeactivationException {
      rethrow;
    } on TimeoutException {
      throw const MatrixAccountDeactivationException(
        'Deleting account timed out. Check your connection and try again.',
      );
    } catch (e) {
      throw MatrixAccountDeactivationException(
        'Failed to delete account: $e',
      );
    } finally {
      httpClient.close(force: true);
    }
  }

  String? _storedPasswordForCurrentUser() {
    final loginUser = currentLoginUsername;
    if (loginUser == null) return null;
    for (final key in _authBox.keys) {
      final value = _authBox.get(key);
      if (value is Map && value['username'] == loginUser) {
        final password = value['password'];
        return password is String ? password : null;
      }
    }
    return null;
  }

  Future<void> _removeStoredCredentialsForCurrentUser() async {
    final loginUser = currentLoginUsername;
    if (loginUser == null) return;
    final keysToDelete = <dynamic>[];
    for (final key in _authBox.keys) {
      final value = _authBox.get(key);
      if (value is Map && value['username'] == loginUser) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await _authBox.delete(key);
    }
  }

  Future<void> setHttpPusher({
    required String pushKey,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    required String profileTag,
    required String pushGatewayUrl,
    String lang = 'en',
  }) async {
    await _setPusher({
      'pushkey': pushKey,
      'kind': 'http',
      'app_id': appId,
      'app_display_name': appDisplayName,
      'device_display_name': deviceDisplayName,
      'profile_tag': profileTag,
      'lang': lang,
      'data': {
        'url': pushGatewayUrl,
      },
    });
  }

  Future<void> removeHttpPusher({
    required String pushKey,
    required String appId,
  }) async {
    await _setPusher({
      'pushkey': pushKey,
      'kind': null,
      'app_id': appId,
      'app_display_name': 'XMO',
      'device_display_name': 'XMO mobile',
      'lang': 'en',
      'data': <String, dynamic>{},
    });
  }

  Future<void> _setPusher(Map<String, dynamic> body) async {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Cannot configure push before login');
    }

    final uri = Uri.parse('$homeserverUrl/_matrix/client/v3/pushers/set');
    final httpClient = io.HttpClient();
    try {
      final request = await httpClient.postUrl(uri);
      request.headers.contentType = io.ContentType.json;
      request.headers.set('Authorization', 'Bearer $token');
      request.write(jsonEncode(body));

      final response = await request.close();
      final responseBody =
          utf8.decode(await consolidateHttpClientResponseBytes(response));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to configure Matrix pusher (${response.statusCode}): '
          '$responseBody',
        );
      }
    } finally {
      httpClient.close(force: true);
    }
  }

  // ─── Rooms ────────────────────────────────────────────────────────────────

  List<Room> getRooms() => _client.rooms.where((room) {
        final type = room.getState(roomTypeStateType)?.content;
        if (type?['kind'] == 'directory') return false;
        if (_isDuplicateSavedMessagesRoom(room)) return false;
        return room.canonicalAlias != '#xmo-user-directory:$matrixServerName';
      }).toList();

  bool isSavedMessagesRoom(Room room) {
    if (_savedMessagesRoomId == room.id) return true;
    final type = room.getState(roomTypeStateType)?.content;
    return type?['is_saved_messages'] == true ||
        type?['kind'] == 'saved' ||
        room.getState(savedMessagesStateType)?.content['enabled'] == true;
  }

  Future<void> _cacheSavedMessagesRoomId(String roomId) async {
    _savedMessagesRoomId = roomId;
    await _authBox.put(_savedMessagesRoomIdKey, roomId);
  }

  bool _isDuplicateSavedMessagesRoom(Room room) {
    if (isSavedMessagesRoom(room)) return false;
    if (room.membership != Membership.join &&
        room.membership != Membership.invite) {
      return false;
    }
    return cleanName(getResolvedDisplayName(room)).trim().toLowerCase() ==
        'saved messages';
  }

  Room? getSavedMessagesRoom() {
    for (final room in _client.rooms) {
      if (room.membership == Membership.join && isSavedMessagesRoom(room)) {
        unawaited(_cacheSavedMessagesRoomId(room.id));
        return room;
      }
    }
    return null;
  }

  Future<int> deleteDuplicateSavedMessagesRooms() async {
    final duplicates = _client.rooms
        .where(_isDuplicateSavedMessagesRoom)
        .toList(growable: false);

    var deleted = 0;
    for (final room in duplicates) {
      try {
        await room.leave();
        deleted++;
      } catch (e) {
        debugPrint(
          '[MatrixService] Failed to leave duplicate Saved Messages room '
          '${room.id}: $e',
        );
      }
    }

    if (deleted > 0) {
      await _client.oneShotSync();
    }
    return deleted;
  }

  Future<Room> getOrCreateSavedMessagesRoom() async {
    final existing = getSavedMessagesRoom();
    if (existing != null) return existing;

    final roomId = await _client.createRoom(
      name: 'Saved Messages',
      preset: CreateRoomPreset.privateChat,
      visibility: null,
      initialState: [
        StateEvent(
          type: roomTypeStateType,
          stateKey: '',
          content: {
            'kind': 'saved',
            'is_saved_messages': true,
          },
        ),
        StateEvent(
          type: savedMessagesStateType,
          stateKey: '',
          content: {'enabled': true},
        ),
        StateEvent(
          type: EventTypes.HistoryVisibility,
          stateKey: '',
          content: {'history_visibility': 'shared'},
        ),
      ],
    );

    await _client.oneShotSync();
    await _cacheSavedMessagesRoomId(roomId);
    return _client.getRoomById(roomId) ?? Room(id: roomId, client: _client);
  }

  /// Get rooms where the user has been invited but hasn't joined yet
  List<Room> getInvitedRooms() {
    return _client.rooms
        .where((r) => r.membership == Membership.invite)
        .toList();
  }

  /// Auto-accept all pending room invites
  Future<void> acceptAllInvites() async {
    final invites = getInvitedRooms();
    for (final room in invites) {
      try {
        await room.join();
        debugPrint('[Matrix] Accepted invite to room: ${room.id}');
      } catch (e) {
        debugPrint('[Matrix] Failed to accept invite to ${room.id}: $e');
      }
    }
  }

  Future<String> createRoom({
    required String name,
    String? topic,
    bool isDirect = false,
  }) async {
    final aliasName = isDirect ? null : _toAliasName(name);
    final initialState = isDirect
        ? privateRoomInitialState()
        : <StateEvent>[
            StateEvent(
              type: EventTypes.HistoryVisibility,
              stateKey: '',
              content: {'history_visibility': 'shared'},
            ),
            publicRoomSecurityState(),
          ];
    try {
      final roomId = await _client.createRoom(
        name: name,
        topic: topic,
        preset: isDirect
            ? CreateRoomPreset.privateChat
            : CreateRoomPreset.publicChat,
        visibility: isDirect ? null : Visibility.public,
        roomAliasName: aliasName,
        isDirect: isDirect,
        initialState: initialState,
      );
      if (!isDirect) {
        cacheGroupId(roomId);
        _ensureDirectoryVisibility(roomId);
      }
      return roomId;
    } catch (e) {
      // If alias is taken, retry without alias — user's display name is unaffected
      if (e.toString().contains('M_ROOM_IN_USE') && !isDirect) {
        debugPrint('[Matrix] Alias taken, retrying without alias');
        final roomId = await _client.createRoom(
          name: name,
          topic: topic,
          preset: CreateRoomPreset.publicChat,
          visibility: Visibility.public,
          isDirect: false,
          initialState: [
            StateEvent(
              type: EventTypes.HistoryVisibility,
              stateKey: '',
              content: {'history_visibility': 'shared'},
            ),
            publicRoomSecurityState(),
          ],
        );
        cacheGroupId(roomId);
        _ensureDirectoryVisibility(roomId);
        return roomId;
      }
      rethrow;
    }
  }

  Future<String> createDirectRoom(String userId) async {
    final roomId = await _client.createRoom(
      invite: [userId],
      preset: CreateRoomPreset.privateChat,
      isDirect: true,
      initialState: privateRoomInitialState([
        StateEvent(
          type: roomTypeStateType,
          stateKey: '',
          content: {'is_direct': true, 'kind': 'direct'},
        ),
      ]),
    );
    await Room(id: roomId, client: _client).addToDirectChat(userId);
    return roomId;
  }

  /// Creates a broadcast channel where only admins can send messages.
  Future<String> createChannel({
    required String name,
    String? topic,
    bool isPublic = true,
  }) async {
    final aliasName = isPublic ? _toAliasName(name) : null;
    final initialState = _channelInitialState(isPublic);
    String roomId;
    try {
      roomId = await _client.createRoom(
        name: name,
        topic: topic,
        preset: isPublic
            ? CreateRoomPreset.publicChat
            : CreateRoomPreset.privateChat,
        visibility: isPublic ? Visibility.public : Visibility.private,
        roomAliasName: aliasName,
        powerLevelContentOverride: {
          'events_default': RoomControlsService.channelPostingPower,
          'users_default': 0,
        },
        initialState: initialState,
      );
    } catch (e) {
      // If alias is taken, retry without alias — display name stays the same
      if (e.toString().contains('M_ROOM_IN_USE') && isPublic) {
        debugPrint('[Matrix] Alias taken, retrying without alias');
        roomId = await _client.createRoom(
          name: name,
          topic: topic,
          preset: CreateRoomPreset.publicChat,
          visibility: Visibility.public,
          powerLevelContentOverride: {
            'events_default': RoomControlsService.channelPostingPower,
            'users_default': 0,
          },
          initialState: _channelInitialState(true),
        );
      } else {
        rethrow;
      }
    }
    // ✅ Cache immediately so it survives hot restart before state syncs
    cacheChannelId(roomId);
    // ✅ Explicitly publish to directory
    if (isPublic) _ensureDirectoryVisibility(roomId);
    return roomId;
  }

  /// State used for rooms where XMO requires end-to-end encryption at creation.
  /// Existing rooms are intentionally not modified because enabling encryption
  /// later changes their security model and cannot recover old plaintext events.
  List<StateEvent> privateRoomInitialState(
      [List<StateEvent> extra = const []]) {
    if (!_client.encryptionEnabled) {
      throw StateError(
        'End-to-end encryption is unavailable on this device. '
        'Update XMO and try again.',
      );
    }

    return <StateEvent>[
      StateEvent(
        type: EventTypes.Encryption,
        stateKey: '',
        content: {
          'algorithm': Client.supportedGroupEncryptionAlgorithms.first,
        },
      ),
      StateEvent(
        type: roomSecurityStateType,
        stateKey: '',
        content: const {
          'version': 1,
          'visibility': 'private',
          'encrypted': true,
          'locked': true,
        },
      ),
      ...extra,
    ];
  }

  StateEvent publicRoomSecurityState() => StateEvent(
        type: roomSecurityStateType,
        stateKey: '',
        content: const {
          'version': 1,
          'visibility': 'public',
          'encrypted': false,
          'locked': true,
        },
      );

  List<StateEvent> _channelInitialState(bool isPublic) {
    final base = <StateEvent>[
      StateEvent(
        type: roomTypeStateType,
        stateKey: '',
        content: {'is_channel': true},
      ),
      StateEvent(
        type: EventTypes.HistoryVisibility,
        stateKey: '',
        content: {'history_visibility': 'shared'},
      ),
    ];
    return isPublic
        ? <StateEvent>[...base, publicRoomSecurityState()]
        : privateRoomInitialState(base);
  }

  /// Converts a human room name to a valid, unique Matrix alias local part.
  /// Appends a short timestamp suffix so users can create channels with
  /// duplicate display names without hitting M_ROOM_IN_USE.
  String _toAliasName(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final suffix = DateTime.now().millisecondsSinceEpoch.toString();
    return '${base}_$suffix';
  }

  /// Explicitly sets a room's directory visibility to public.
  /// Tracks already-published rooms to avoid redundant API calls.
  void _ensureDirectoryVisibility(String roomId) {
    if (_publishedRoomIds.contains(roomId)) return;
    _publishedRoomIds.add(roomId);
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        await _client.setRoomVisibilityOnDirectory(roomId,
            visibility: Visibility.public);
        debugPrint('[Matrix] Published room $roomId to public directory');
      } catch (e) {
        debugPrint('[Matrix] Failed to publish room to directory: $e');
      }
    });
  }

  // ─── Channel ID Cache ──────────────────────────────────────────────────────

  /// Returns true if this room is known to be a channel (from persistent cache).
  bool isKnownChannel(String roomId) => _channelIdCache.contains(roomId);

  /// Returns true if this room is known to be a group (from persistent cache).
  bool isKnownGroup(String roomId) => _groupIdCache.contains(roomId);

  /// Persist a room ID as a channel. Survives app restarts.
  void cacheChannelId(String roomId) {
    if (_groupIdCache.remove(roomId)) {
      _groupBox.put('ids', _groupIdCache.toList());
    }
    if (_channelIdCache.add(roomId)) {
      final list = _channelIdCache.toList();
      _channelBox.put('ids', list);
    }
  }

  /// Persist a room ID as a group. Survives app restarts.
  void cacheGroupId(String roomId) {
    if (_channelIdCache.remove(roomId)) {
      _channelBox.put('ids', _channelIdCache.toList());
    }
    if (_groupIdCache.add(roomId)) {
      final list = _groupIdCache.toList();
      _groupBox.put('ids', list);
    }
  }

  /// Load the persistent channel cache from Hive on startup.
  void _loadChannelCache() {
    final stored = _channelBox.get('ids', defaultValue: <dynamic>[]);
    if (stored is List) {
      _channelIdCache.addAll(stored.whereType<String>());
    }
  }

  /// Load the persistent group cache from Hive on startup.
  void _loadGroupCache() {
    final stored = _groupBox.get('ids', defaultValue: <dynamic>[]);
    if (stored is List) {
      _groupIdCache.addAll(stored.whereType<String>());
    }
  }

  /// After a sync, scan rooms and retroactively cache any detected channels.
  /// Also publishes non-direct rooms to the public directory if they aren't listed.
  void scanAndCacheChannels() {
    for (final room in _client.rooms) {
      final kind = classifyRoomKind(
        typeContent: room.getState(roomTypeStateType)?.content,
        powerLevelsContent: room.getState('m.room.power_levels')?.content,
        isDirectChat: room.isDirectChat,
      );
      if (kind == XmoRoomKind.channel) {
        cacheChannelId(room.id);
        continue;
      }
      if (kind == XmoRoomKind.saved) {
        continue;
      }
      if (kind == XmoRoomKind.group) {
        cacheGroupId(room.id);
      }
    }
    // Retroactively publish non-direct rooms to the directory (once per session)
    if (!_hasPublishedExisting) {
      _hasPublishedExisting = true;
      _publishExistingRoomsToDirectory();
    }
  }

  /// Retroactively ensures all non-direct, public-preset rooms are listed
  /// in the public room directory. Fixes rooms created before the visibility fix.
  void _publishExistingRoomsToDirectory() {
    for (final room in _client.rooms) {
      if (room.isDirectChat) continue;
      if (room.membership != Membership.join) continue;
      if (isSavedMessagesRoom(room)) continue;
      final joinRule = room.getState(EventTypes.RoomJoinRules)?.content;
      final rawJoinRule = joinRule?['join_rule']?.toString();
      if (rawJoinRule != 'public') continue;
      // Only publish rooms the current user has admin power in
      final ownPower = room.ownPowerLevel;
      if (ownPower < 50) continue;
      _ensureDirectoryVisibility(room.id);
    }
  }

  Future<void> joinRoom(String roomIdOrAlias) async {
    final identifier = extractRoomIdentifier(roomIdOrAlias) ?? roomIdOrAlias;
    await _client.joinRoom(identifier);
    try {
      await _client.oneShotSync();
      scanAndCacheChannels();
    } catch (e) {
      debugPrint('[Matrix] Joined room, but immediate type sync failed: $e');
    }
  }

  Future<bool> isPublicRoomChannel(
    String roomId, {
    bool forceRefresh = false,
  }) async {
    final cachedIsChannel = isKnownChannel(roomId);
    final cachedIsGroup = isKnownGroup(roomId);
    if (!forceRefresh) {
      if (cachedIsChannel) return true;
      if (cachedIsGroup) return false;
    }

    try {
      final typeState = await _client.getRoomStateWithKey(
        roomId,
        roomTypeStateType,
        '',
      );
      final kind = classifyRoomKind(
        typeContent: typeState,
        isDirectChat: false,
      );
      if (kind == XmoRoomKind.channel) {
        cacheChannelId(roomId);
        return true;
      }
      if (kind == XmoRoomKind.group) {
        cacheGroupId(roomId);
        return false;
      }
    } catch (e) {
      debugPrint('[RoomType] Could not read xmo.room.type for $roomId: $e');
    }

    try {
      final powerLevels = await _client.getRoomStateWithKey(
        roomId,
        EventTypes.RoomPowerLevels,
        '',
      );
      if (powerLevelsMarkChannel(powerLevels)) {
        cacheChannelId(roomId);
        return true;
      }
    } catch (e) {
      debugPrint('[RoomType] Could not read power levels for $roomId: $e');
    }

    if (cachedIsChannel) return true;
    if (cachedIsGroup) return false;
    return false;
  }

  /// Searches the server's public room directory for channels/rooms.
  /// Uses a three-pronged approach (mirrors how user search works):
  ///   1. Server-side search via filter (Synapse directory index)
  ///   2. Broad fetch + client-side filter (catches poor indexing)
  ///   3. Room alias resolution fallback (direct lookup by name)
  Future<List<PublicRoomsChunk>> searchPublicRooms(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      final result = await _client.queryPublicRooms(limit: 200);
      return result.chunk;
    }

    final seen = <String>{};
    final combined = <PublicRoomsChunk>[];

    // Direct invite lookup: pasted matrix.to links, raw room IDs, or aliases.
    final directIdentifier = extractRoomIdentifier(trimmedQuery);
    if (directIdentifier != null) {
      final room = await _publicRoomChunkFromIdentifier(directIdentifier);
      if (room != null && seen.add(room.roomId)) {
        combined.add(room);
      }
    }

    // Prong 1: Server-side search (Synapse directory index)
    try {
      final serverResult = await _client.queryPublicRooms(
        limit: 100,
        filter: PublicRoomQueryFilter(genericSearchTerm: trimmedQuery),
      );
      for (final room in serverResult.chunk) {
        if (seen.add(room.roomId)) combined.add(room);
      }
      debugPrint(
          '[PublicSearch] Server-side returned ${serverResult.chunk.length} results');
    } catch (e) {
      debugPrint('[PublicSearch] Server-side search failed: $e');
    }

    // Prong 2: Broad fetch + client-side filter (catches poor indexing)
    try {
      final allResult = await _client.queryPublicRooms(limit: 200);
      final lowerQuery = trimmedQuery.toLowerCase();
      for (final room in allResult.chunk) {
        if (seen.contains(room.roomId)) continue;
        final name = room.name?.toLowerCase() ?? '';
        final topic = room.topic?.toLowerCase() ?? '';
        final id = room.roomId.toLowerCase();
        if (name.contains(lowerQuery) ||
            topic.contains(lowerQuery) ||
            id.contains(lowerQuery)) {
          seen.add(room.roomId);
          combined.add(room);
        }
      }
    } catch (e) {
      debugPrint('[PublicSearch] Broad fetch failed: $e');
    }

    // Prong 3: Room alias resolution fallback (like user search by ID)
    // Try to resolve a local room alias directly; works even if directory is empty.
    if (combined.isEmpty) {
      try {
        final aliasName = trimmedQuery
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
        final serverName = _client.userID?.split(':').last ?? matrixServerName;
        final fullAlias = '#$aliasName:$serverName';
        debugPrint('[PublicSearch] Trying alias resolution: $fullAlias');
        final aliasResult = await _client.getRoomIdByAlias(fullAlias);
        final roomId = aliasResult.roomId;
        if (roomId != null && !seen.contains(roomId)) {
          // Fetch room details to build a proper PublicRoomsChunk
          seen.add(roomId);
          combined.add(PublicRoomsChunk(
            numJoinedMembers: 0,
            roomId: roomId,
            worldReadable: false,
            guestCanJoin: false,
            name: trimmedQuery,
            canonicalAlias: fullAlias,
          ));
          debugPrint('[PublicSearch] Found room via alias: $roomId');
        }
      } catch (e) {
        debugPrint(
            '[PublicSearch] Alias resolution failed (expected if no match): $e');
      }
    }

    debugPrint(
        '[PublicSearch] Combined total: ${combined.length} results for "$trimmedQuery"');
    return combined;
  }

  Future<PublicRoomsChunk?> _publicRoomChunkFromIdentifier(
    String identifier,
  ) async {
    if (identifier.startsWith('#')) {
      try {
        final aliasResult = await _client.getRoomIdByAlias(identifier);
        final roomId = aliasResult.roomId;
        if (roomId == null) return null;
        return PublicRoomsChunk(
          numJoinedMembers: 0,
          roomId: roomId,
          worldReadable: false,
          guestCanJoin: false,
          name: identifier,
          canonicalAlias: identifier,
        );
      } catch (e) {
        debugPrint('[PublicSearch] Invite alias lookup failed: $e');
        return null;
      }
    }

    if (identifier.startsWith('!')) {
      final joinedRoom = getRoomById(identifier);
      return PublicRoomsChunk(
        numJoinedMembers: joinedRoom?.summary.mJoinedMemberCount ?? 0,
        roomId: identifier,
        worldReadable: false,
        guestCanJoin: false,
        name: joinedRoom != null
            ? getResolvedDisplayName(joinedRoom)
            : identifier,
      );
    }

    return null;
  }

  Room? getRoomById(String roomId) => _client.getRoomById(roomId);

  Room? getJoinedRoomById(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) return null;
    return room;
  }

  bool isDirectRoom(Room room) {
    return classifyRoomKind(
          typeContent: room.getState(roomTypeStateType)?.content,
          powerLevelsContent:
              room.getState(EventTypes.RoomPowerLevels)?.content,
          isDirectChat: room.isDirectChat,
        ) ==
        XmoRoomKind.direct;
  }

  String? getDirectPeerUserId(Room room) {
    final directChatMatrixID = room.directChatMatrixID;
    if (directChatMatrixID != null) return directChatMatrixID;
    if (!isDirectRoom(room)) return null;

    final myUserId = _client.userID;
    if (myUserId == null) return null;

    final participantIds = _activeParticipantIds(room)
      ..removeWhere((userId) => userId == myUserId);
    return participantIds.length == 1 ? participantIds.first : null;
  }

  String getResolvedDisplayName(Room room) {
    if (room.name.isNotEmpty) return room.name;

    final peerUserId = getDirectPeerUserId(room);
    if (peerUserId != null) {
      return room
          .unsafeGetUserFromMemoryOrFallback(peerUserId)
          .calcDisplayname();
    }

    return room.getLocalizedDisplayname();
  }

  bool looksLikeLegacyDirectRoom(Room room, String otherUserId) {
    if (room.name.isNotEmpty || room.canonicalAlias.isNotEmpty) return false;

    final typeContent = room.getState(roomTypeStateType)?.content;
    if (typeContent?['is_group'] == true ||
        typeContent?['is_channel'] == true) {
      return false;
    }

    final participants = _activeParticipantIds(room);
    final myUserId = _client.userID;
    if (myUserId == null) return false;

    if (participants.length != 2 ||
        !participants.contains(myUserId) ||
        !participants.contains(otherUserId)) {
      return false;
    }

    final kind = classifyRoomKind(
      typeContent: typeContent,
      powerLevelsContent: room.getState(EventTypes.RoomPowerLevels)?.content,
      isDirectChat: room.isDirectChat,
    );
    return kind == null || kind == XmoRoomKind.direct;
  }

  Future<void> markRoomAsDirect(String roomId, String otherUserId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    await _client.setRoomStateWithKey(
      roomId,
      roomTypeStateType,
      '',
      {'is_direct': true, 'kind': 'direct'},
    );
    await room.addToDirectChat(otherUserId);
  }

  Future<void> repairDirectChatMappings() async {
    for (final room in _client.rooms) {
      if (room.membership != Membership.join &&
          room.membership != Membership.invite) {
        continue;
      }

      final peerUserId = getDirectPeerUserId(room);
      if (peerUserId == null || room.directChatMatrixID == peerUserId) {
        continue;
      }

      try {
        await room.addToDirectChat(peerUserId);
      } catch (e) {
        debugPrint(
            '[Matrix] Failed to repair direct mapping for ${room.id}: $e');
      }
    }
  }

  Set<String> _activeParticipantIds(Room room) {
    final participantIds = <String>{};
    for (final user in room.getParticipants()) {
      participantIds.add(user.id);
    }

    final states = room.states[EventTypes.RoomMember];
    if (states != null) {
      for (final state in states.values) {
        final membership = state.content['membership'];
        if (membership == 'invite' || membership == 'join') {
          final stateKey = state.stateKey;
          if (stateKey != null && stateKey.isNotEmpty) {
            participantIds.add(stateKey);
          }
        }
      }
    }

    return participantIds;
  }

  Future<XmoInviteLink> generateTrackedInviteLink(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final existingLinks = await getInviteLinks(roomId);
    final now = DateTime.now();
    final linkId = now.microsecondsSinceEpoch.toString();
    final link = XmoInviteLink(
      linkId: linkId,
      url: '${buildMatrixToLink(room.id)}?xmo_invite=$linkId',
      roomId: room.id,
      createdAt: now,
      createdBy: _client.userID ?? '',
    );

    await _saveInviteLinks(roomId, [...existingLinks, link]);
    return link;
  }

  Future<List<XmoInviteLink>> getInviteLinks(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final state = room.getState(_inviteLinksStateType);
    final rawLinks = state?.content['links'];
    if (rawLinks is! List) return const [];

    return rawLinks
        .whereType<Map>()
        .map(XmoInviteLink.fromJson)
        .where((link) => link.linkId.isNotEmpty && link.roomId.isNotEmpty)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<XmoInviteLink?> getActiveInviteLink(String roomId) async {
    final links = await getInviteLinks(roomId);
    for (final link in links) {
      if (link.canBeUsed) return link;
    }
    return null;
  }

  Future<void> revokeInviteLink(String roomId, String linkId) async {
    final links = await getInviteLinks(roomId);
    final updatedLinks = links.map((link) {
      if (link.linkId != linkId) return link;
      return link.copyWith(isActive: false);
    }).toList();

    await _saveInviteLinks(roomId, updatedLinks);
  }

  Future<void> _saveInviteLinks(
    String roomId,
    List<XmoInviteLink> links,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    await room.client.setRoomStateWithKey(
      roomId,
      _inviteLinksStateType,
      '',
      {'links': links.map((link) => link.toJson()).toList()},
    );
  }

  // ─── Messaging ────────────────────────────────────────────────────────────

  Future<void> sendGroupCallPushMarker({
    required Room room,
    required String groupCallId,
    required bool video,
  }) async {
    try {
      await room.sendEvent({
        'msgtype': 'm.notice',
        'body': 'Incoming ${video ? 'video' : 'voice'} call',
        'xmo_event': groupCallPushMarkerEvent,
        'xmo_push_type': 'call',
        'xmo_call_kind': 'group',
        'group_call': true,
        'group_call_id': groupCallId,
        'call_id': groupCallId,
        'm.call.id': groupCallId,
        'call_type': video ? 'video' : 'voice',
        'm.type': video ? 'm.video' : 'm.voice',
        'm.intent': 'm.prompt',
      });
    } catch (e) {
      debugPrint('[MatrixService] Failed to send group call push marker: $e');
    }
  }

  Future<void> sendMessage(
    String roomId,
    String message, {
    Map<String, dynamic> extraContent = const {},
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');
    final linkPreview = await _buildLinkPreview(message);
    if (linkPreview == null) {
      if (extraContent.isEmpty) {
        await room.sendTextEvent(message);
      } else {
        await room.sendEvent({
          'msgtype': 'm.text',
          'body': message,
          ...extraContent,
        });
      }
      return;
    }

    await room.sendEvent({
      'msgtype': 'm.text',
      'body': message,
      'com.xmo.link_preview': linkPreview,
      ...extraContent,
    });
  }

  Future<void> sendSticker({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final preparedSticker = await _prepareMediaUpload(
      room,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final stickerMxc = await _client.uploadContent(
      preparedSticker.bytes,
      filename: fileName,
      contentType: preparedSticker.contentType,
    );

    await room.sendEvent({
      'body': fileName,
      if (preparedSticker.encryptedFile == null) 'url': stickerMxc.toString(),
      if (preparedSticker.encryptedFile != null)
        'file': _encryptedFileContent(
          preparedSticker.encryptedFile!,
          stickerMxc,
          mimeType: mimeType,
        ),
      'info': {
        'mimetype': mimeType,
        'size': bytes.length,
      },
    }, type: EventTypes.Sticker);
  }

  Future<void> sendPoll({
    required String roomId,
    required String question,
    required List<String> options,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final cleanQuestion = question.trim();
    final answers = <Map<String, dynamic>>[];
    for (var i = 0; i < options.length; i++) {
      final option = options[i].trim();
      if (option.isEmpty) continue;
      answers.add({
        'id': 'xmo_poll_${DateTime.now().microsecondsSinceEpoch}_$i',
        'org.matrix.msc1767.text': option,
        'm.text': option,
      });
    }
    if (cleanQuestion.isEmpty || answers.length < 2) {
      throw Exception('Poll needs a question and at least two options');
    }

    final pollStart = {
      'question': {
        'org.matrix.msc1767.text': cleanQuestion,
        'm.text': cleanQuestion,
      },
      'kind': 'org.matrix.msc3381.poll.undisclosed',
      'max_selections': 1,
      'answers': answers,
    };

    await room.sendEvent({
      'body': cleanQuestion,
      'org.matrix.msc1767.text': cleanQuestion,
      'm.text': cleanQuestion,
      'org.matrix.msc3381.poll.start': pollStart,
      'm.poll.start': pollStart,
    }, type: 'm.poll.start');
  }

  Future<void> sendPollResponse({
    required String roomId,
    required String pollEventId,
    required String answerId,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final response = {
      'answers': [answerId],
    };

    await room.sendEvent({
      'm.relates_to': {
        'rel_type': 'm.reference',
        'event_id': pollEventId,
      },
      'org.matrix.msc3381.poll.response': response,
      'm.poll.response': response,
    }, type: 'm.poll.response');
  }

  Future<Map<String, dynamic>?> _buildLinkPreview(String message) async {
    final match = RegExp(
      r'((https?:\/\/|www\.)[^\s<>()]+|(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:com|org|net|edu|gov|io|co|in|me|app|dev|ai|info|biz|xyz|site|online|store|tech|link|ly|to|tv|uk|us|ca|au|de|fr|jp|cn|ru|br|za|nl|it|es|se|no|fi|ch|be|at|dk|pl|ie|sg|ae|sa|qa|kw|om|bh|pk|bd|lk|np|id|my|th|vn|ph)(?:\/[^\s<>()]*)?)',
      caseSensitive: false,
    ).firstMatch(message);
    if (match == null) return null;

    var url = match.group(0) ?? '';
    url = url.replaceAll(RegExp(r'[.,!?;:]+$'), '');
    if (url.contains('@')) return null;
    final normalizedUrl =
        url.startsWith(RegExp(r'https?://', caseSensitive: false))
            ? url
            : 'https://$url';
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || uri.host.isEmpty) return null;

    final fallback = {
      'url': normalizedUrl,
      'host': uri.host,
      'title':
          uri.host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), ''),
    };

    final richPreview = await _fetchRichLinkPreview(uri, fallback).timeout(
      const Duration(milliseconds: 1200),
      onTimeout: () => fallback,
    );
    return richPreview ?? fallback;
  }

  Future<Map<String, dynamic>?> _fetchRichLinkPreview(
    Uri uri,
    Map<String, dynamic> fallback,
  ) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') return fallback;

    final client = io.HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 900)
      ..userAgent = 'XMO/1.0 link preview';

    try {
      final request = await client.getUrl(uri).timeout(
            const Duration(milliseconds: 900),
          );
      request.headers.set(
        io.HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.followRedirects = true;
      request.maxRedirects = 4;

      final response = await request.close().timeout(
            const Duration(milliseconds: 1200),
          );
      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      if (response.statusCode < 200 ||
          response.statusCode >= 400 ||
          (contentType != null && !contentType.contains('html'))) {
        return fallback;
      }

      final chunks = <int>[];
      var total = 0;
      await for (final chunk in response) {
        total += chunk.length;
        if (total > 320 * 1024) break;
        chunks.addAll(chunk);
      }

      if (chunks.isEmpty) return fallback;
      final html = utf8.decode(chunks, allowMalformed: true);
      final title = _firstNonEmpty([
            _htmlMetaContent(html, 'og:title'),
            _htmlMetaContent(html, 'twitter:title'),
            _htmlTitle(html),
          ]) ??
          fallback['title']?.toString();
      final description = _firstNonEmpty([
        _htmlMetaContent(html, 'og:description'),
        _htmlMetaContent(html, 'twitter:description'),
        _htmlMetaContent(html, 'description'),
      ]);
      final siteName = _firstNonEmpty([
        _htmlMetaContent(html, 'og:site_name'),
        fallback['host']?.toString(),
      ]);
      final image = _firstNonEmpty([
        _htmlMetaContent(html, 'og:image'),
        _htmlMetaContent(html, 'twitter:image'),
        _htmlMetaContent(html, 'twitter:image:src'),
      ]);
      final imageUrl = image == null ? null : _absoluteUrl(uri, image);

      return {
        ...fallback,
        if (title != null && title.isNotEmpty) 'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (siteName != null && siteName.isNotEmpty) 'site_name': siteName,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
      };
    } catch (e) {
      debugPrint('[MatrixService] Rich link preview failed for $uri: $e');
      return fallback;
    } finally {
      client.close(force: true);
    }
  }

  String? _htmlMetaContent(String html, String key) {
    final escapedKey = RegExp.escape(key);
    final patterns = [
      RegExp(
        '<meta\\s+[^>]*(?:property|name)=["\\\']$escapedKey["\\\'][^>]*content=["\\\']([^"\\\']+)["\\\'][^>]*>',
        caseSensitive: false,
      ),
      RegExp(
        '<meta\\s+[^>]*content=["\\\']([^"\\\']+)["\\\'][^>]*(?:property|name)=["\\\']$escapedKey["\\\'][^>]*>',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final value = match?.group(1);
      if (value != null && value.trim().isNotEmpty) {
        return _cleanHtmlText(value);
      }
    }
    return null;
  }

  String? _htmlTitle(String html) {
    final match = RegExp(
      r'<title[^>]*>(.*?)<\/title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final value = match?.group(1);
    if (value == null || value.trim().isEmpty) return null;
    return _cleanHtmlText(value);
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String _cleanHtmlText(String value) {
    return _decodeHtmlEntities(
      value.replaceAll(RegExp(r'\s+'), ' ').trim(),
    );
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  String? _absoluteUrl(Uri base, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    return base.resolveUri(uri).toString();
  }

  Future<void> sendAudio({
    required String roomId,
    required Uint8List audioBytes,
    required String fileName,
    required String mimeType,
    required int durationMs,
    bool isVoiceMessage = true,
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
    Map<String, dynamic>? xmoStream,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final preparedAudio = await _prepareMediaUpload(
      room,
      bytes: audioBytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final audioMxc = await _uploadContentWithProgress(
      preparedAudio.bytes,
      filename: fileName,
      contentType: preparedAudio.contentType,
      onProgress: onUploadProgress,
      isCancelled: isCancelled,
    );
    _throwIfCancelled(isCancelled);

    await room.sendEvent(
      XmoMediaCompatibility.withOptionalStream(
        matrixContent: {
          'msgtype': 'm.audio',
          'body': fileName,
          'filename': fileName,
          if (preparedAudio.encryptedFile == null) 'url': audioMxc.toString(),
          if (preparedAudio.encryptedFile != null)
            'file': _encryptedFileContent(
                preparedAudio.encryptedFile!, audioMxc,
                mimeType: mimeType),
          'info': {
            'mimetype': mimeType,
            'size': audioBytes.length,
            if (durationMs > 0) 'duration': durationMs,
          },
          if (isVoiceMessage) 'org.matrix.msc3245.voice': {},
        },
        xmoStream: xmoStream,
      ),
    );
  }

  Future<void> forwardMessage({
    required Event event,
    required String targetRoomId,
  }) async {
    if (event.redacted) {
      throw Exception('Deleted messages cannot be forwarded');
    }
    if (event.type != EventTypes.Message && event.type != EventTypes.Sticker) {
      throw Exception('This message type cannot be forwarded');
    }

    final targetRoom = _client.getRoomById(targetRoomId);
    if (targetRoom == null) throw Exception('Room not found: $targetRoomId');
    if (!targetRoom.canSendEvent(EventTypes.Message)) {
      throw Exception('You cannot send messages in this chat');
    }

    final content = _forwardableContent(event);
    await targetRoom.sendEvent(content, type: event.type);
  }

  Map<String, dynamic> _forwardableContent(Event event) {
    final editedContent = event.content['m.new_content'];
    final source = editedContent is Map
        ? Map<String, dynamic>.from(editedContent)
        : Map<String, dynamic>.from(event.content);

    final copied = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
    copied.remove('m.relates_to');
    copied.remove('m.new_content');
    copied['xmo.forwarded'] = {
      'event_id': event.eventId,
      'room_id': event.room.id,
      'sender': event.senderId,
    };

    if (copied['body'] is String) {
      copied['body'] = _stripReplyFallback(copied['body'] as String);
    }
    if (copied['formatted_body'] is String) {
      copied['formatted_body'] =
          _stripFormattedReplyFallback(copied['formatted_body'] as String);
      if ((copied['formatted_body'] as String).trim().isEmpty) {
        copied.remove('formatted_body');
        copied.remove('format');
      }
    }

    return copied;
  }

  String _stripReplyFallback(String body) {
    if (!body.startsWith('> ')) return body;
    final lines = body.split('\n');
    final separatorIndex = lines.indexWhere((line) => line.trim().isEmpty);
    if (separatorIndex == -1 || separatorIndex == lines.length - 1) {
      return body;
    }
    return lines.sublist(separatorIndex + 1).join('\n');
  }

  String _stripFormattedReplyFallback(String html) {
    final replyEnd = html.indexOf('</mx-reply>');
    if (replyEnd == -1) return html;
    return html.substring(replyEnd + '</mx-reply>'.length).trimLeft();
  }

  /// Sends a file/image/video to a room through XMO's media path.
  Future<void> sendFile(String roomId, MatrixFile file) async {
    await sendFileWithProgress(
      roomId: roomId,
      bytes: file.bytes,
      fileName: file.name,
      mimeType: file.mimeType,
    );
  }

  Future<void> sendFileWithProgress({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
    Map<String, dynamic>? xmoStream,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final preparedFile = await _prepareMediaUpload(
      room,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final fileMxc = await _uploadContentWithProgress(
      preparedFile.bytes,
      filename: fileName,
      contentType: preparedFile.contentType,
      onProgress: onUploadProgress,
      isCancelled: isCancelled,
    );
    _throwIfCancelled(isCancelled);

    await room.sendEvent(
      XmoMediaCompatibility.withOptionalStream(
        matrixContent: {
          'msgtype': 'm.file',
          'body': fileName,
          'filename': fileName,
          if (preparedFile.encryptedFile == null) 'url': fileMxc.toString(),
          if (preparedFile.encryptedFile != null)
            'file': _encryptedFileContent(preparedFile.encryptedFile!, fileMxc,
                mimeType: mimeType),
          'info': {
            'mimetype': mimeType,
            'size': bytes.length,
          },
        },
        xmoStream: xmoStream,
      ),
    );
  }

  Future<void> sendImageWithCaption({
    required String roomId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String caption = '',
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
    Map<String, dynamic>? xmoStream,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    final preparedImage = await _prepareMediaUpload(
      room,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final imageMxc = await _uploadContentWithProgress(
      preparedImage.bytes,
      filename: fileName,
      contentType: preparedImage.contentType,
      onProgress: onUploadProgress,
      isCancelled: isCancelled,
    );
    _throwIfCancelled(isCancelled);
    final cleanCaption = caption.trim();

    await room.sendEvent(
      XmoMediaCompatibility.withOptionalStream(
        matrixContent: {
          'msgtype': 'm.image',
          'body': cleanCaption.isEmpty ? fileName : cleanCaption,
          'filename': fileName,
          if (cleanCaption.isNotEmpty) 'xmo_caption': cleanCaption,
          if (preparedImage.encryptedFile == null) 'url': imageMxc.toString(),
          if (preparedImage.encryptedFile != null)
            'file': _encryptedFileContent(
                preparedImage.encryptedFile!, imageMxc,
                mimeType: mimeType),
          'info': {
            'mimetype': mimeType,
            'size': bytes.length,
          },
        },
        xmoStream: xmoStream,
      ),
    );
  }

  /// Sends a video with an embedded thumbnail.
  /// The SDK's MatrixVideoFile has no thumbnail param, so we manually:
  ///   1. Upload thumbnail bytes → thumbnail mxc URL
  ///   2. Upload video bytes    → video mxc URL
  ///   3. Call room.sendEvent() with both URLs in content
  Future<void> sendVideoWithThumbnail({
    required String roomId,
    required Uint8List videoBytes,
    required String videoFileName,
    required String videoMimeType,
    Uint8List? thumbBytes,
    int? videoWidth,
    int? videoHeight,
    int? durationMs,
    int? thumbnailWidth,
    int? thumbnailHeight,
    String caption = '',
    void Function(int uploadedBytes, int totalBytes)? onUploadProgress,
    bool Function()? isCancelled,
    Map<String, dynamic>? xmoStream,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found: $roomId');

    var effectiveVideoBytes = videoBytes;
    var effectiveVideoFileName = videoFileName;
    var effectiveVideoMimeType = videoMimeType;
    try {
      _throwIfCancelled(isCancelled);
      final normalized = await _chunkedMediaUploadService.normalizeVideoSource(
        videoBytes: videoBytes,
        videoFileName: videoFileName,
        videoMimeType: videoMimeType,
        durationMs: durationMs,
        isCancelled: isCancelled,
      );
      _throwIfCancelled(isCancelled);
      if (normalized != null) {
        effectiveVideoBytes = normalized.bytes;
        effectiveVideoFileName = normalized.fileName;
        effectiveVideoMimeType = normalized.mimeType;
        debugPrint(
          '[sendVideo] Normalized video source '
          '(${videoBytes.length} -> ${effectiveVideoBytes.length} bytes).',
        );
      }
    } on XmoChunkedMediaUploadCancelledException {
      throw const MatrixUploadCancelledException();
    } catch (e) {
      debugPrint('[sendVideo] Video source normalization skipped: $e');
    }

    // Step 1: Upload video
    debugPrint(
      '[sendVideo] Uploading video (${effectiveVideoBytes.length} bytes)...',
    );
    final preparedVideo = await _prepareMediaUpload(
      room,
      bytes: effectiveVideoBytes,
      fileName: effectiveVideoFileName,
      mimeType: effectiveVideoMimeType,
    );
    final videoMxc = await _uploadContentWithProgress(
      preparedVideo.bytes,
      filename: effectiveVideoFileName,
      contentType: preparedVideo.contentType,
      onProgress: onUploadProgress,
      isCancelled: isCancelled,
    );
    _throwIfCancelled(isCancelled);
    debugPrint('[sendVideo] Video uploaded: $videoMxc');

    // Step 2: Build info map
    final info = <String, dynamic>{
      'mimetype': effectiveVideoMimeType,
      'size': effectiveVideoBytes.length,
      if (videoWidth != null && videoWidth > 0) 'w': videoWidth,
      if (videoHeight != null && videoHeight > 0) 'h': videoHeight,
      if (durationMs != null && durationMs > 0) 'duration': durationMs,
    };

    // Step 3: Upload thumbnail if we have one and embed it in info
    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      try {
        _throwIfCancelled(isCancelled);
        debugPrint(
            '[sendVideo] Uploading thumbnail (${thumbBytes.length} bytes)...');
        final preparedThumb = await _prepareMediaUpload(
          room,
          bytes: thumbBytes,
          fileName: '${effectiveVideoFileName}_thumb.jpg',
          mimeType: 'image/jpeg',
        );
        final thumbMxc = await _client.uploadContent(
          preparedThumb.bytes,
          filename: '${effectiveVideoFileName}_thumb.jpg',
          contentType: preparedThumb.contentType,
        );
        debugPrint('[sendVideo] Thumbnail uploaded: $thumbMxc');
        if (preparedThumb.encryptedFile == null) {
          info['thumbnail_url'] = thumbMxc.toString();
        } else {
          info['thumbnail_file'] = _encryptedFileContent(
            preparedThumb.encryptedFile!,
            thumbMxc,
            mimeType: 'image/jpeg',
          );
        }
        info['thumbnail_info'] = {
          'mimetype': 'image/jpeg',
          'size': thumbBytes.length,
          if (thumbnailWidth != null && thumbnailWidth > 0) 'w': thumbnailWidth,
          if (thumbnailHeight != null && thumbnailHeight > 0)
            'h': thumbnailHeight,
        };
      } catch (e) {
        if (e is MatrixUploadCancelledException) rethrow;
        debugPrint('[sendVideo] Thumbnail upload failed (non-fatal): $e');
      }
    }

    final cleanCaption = caption.trim();
    _throwIfCancelled(isCancelled);
    final shouldAttachXmoStream = preparedVideo.encryptedFile != null;
    final effectiveXmoStream = shouldAttachXmoStream
        ? xmoStream ??
            await _buildLargeVideoStreamManifest(
              videoBytes: effectiveVideoBytes,
              videoFileName: effectiveVideoFileName,
              videoMimeType: effectiveVideoMimeType,
              durationMs: durationMs,
              isCancelled: isCancelled,
            )
        : null;
    _throwIfCancelled(isCancelled);

    // Step 4: Send the m.video event with both URLs
    await room.sendEvent(
      XmoMediaCompatibility.withOptionalStream(
        matrixContent: {
          'msgtype': 'm.video',
          'body': cleanCaption.isEmpty ? effectiveVideoFileName : cleanCaption,
          'filename': effectiveVideoFileName,
          if (cleanCaption.isNotEmpty) 'xmo_caption': cleanCaption,
          if (preparedVideo.encryptedFile == null) 'url': videoMxc.toString(),
          if (preparedVideo.encryptedFile != null)
            'file': _encryptedFileContent(
                preparedVideo.encryptedFile!, videoMxc,
                mimeType: effectiveVideoMimeType),
          'info': info,
        },
        xmoStream: effectiveXmoStream,
      ),
    );
    debugPrint('[sendVideo] Event sent.');
  }

  Future<Map<String, dynamic>?> _buildLargeVideoStreamManifest({
    required Uint8List videoBytes,
    required String videoFileName,
    required String videoMimeType,
    required int? durationMs,
    required bool Function()? isCancelled,
  }) async {
    if (!_chunkedMediaUploadService.shouldUploadAsStream(
      size: videoBytes.length,
      mimeType: videoMimeType,
    )) {
      return null;
    }

    debugPrint(
      '[sendVideo] Uploading encrypted stream chunks (${videoBytes.length} bytes)...',
    );
    try {
      final manifest = await _chunkedMediaUploadService.uploadVideoStream(
        videoBytes: videoBytes,
        videoFileName: videoFileName,
        videoMimeType: videoMimeType,
        durationMs: durationMs,
        isCancelled: isCancelled,
        uploadChunk: ({
          required encryptedBytes,
          required fileName,
          required contentType,
          required chunkIndex,
        }) async {
          final azureStorage = _azureChunkStorage;
          if (azureStorage != null) {
            try {
              return await azureStorage.uploadEncryptedChunk(
                encryptedBytes: encryptedBytes,
                fileName: fileName,
                contentType: contentType,
                chunkIndex: chunkIndex,
              );
            } catch (e) {
              debugPrint(
                '[sendVideo] Azure stream chunk upload failed; '
                'falling back to Matrix media: $e',
              );
            }
          }
          return _uploadMatrixStreamChunk(
            encryptedBytes: encryptedBytes,
            fileName: fileName,
            contentType: contentType,
          );
        },
      );
      debugPrint(
        '[sendVideo] Encrypted stream chunks uploaded: '
        '${manifest.sourceQuality?.chunks.length ?? 0}',
      );
      return manifest.toJson();
    } on XmoChunkedMediaUploadCancelledException {
      throw const MatrixUploadCancelledException();
    } catch (e) {
      debugPrint(
          '[sendVideo] Stream chunk upload failed; sending fallback only: $e');
      return null;
    }
  }

  AzureBlobChunkStorageService? get _azureChunkStorage {
    if (!AppConfig.useAzureBlobChunks) return null;
    final endpoint = Uri.tryParse(AppConfig.azureChunkSignUrl.trim());
    if (endpoint == null || !endpoint.hasScheme) return null;
    return _azureBlobChunkStorageService ??=
        AzureBlobChunkStorageService(signingEndpoint: endpoint);
  }

  Future<Uri> _uploadMatrixStreamChunk({
    required Uint8List encryptedBytes,
    required String fileName,
    required String contentType,
  }) {
    return _client.uploadContent(
      encryptedBytes,
      filename: fileName,
      contentType: contentType,
    );
  }

  Future<_PreparedMediaUpload> _prepareMediaUpload(
    Room room, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (!room.encrypted || !_client.fileEncryptionEnabled) {
      return _PreparedMediaUpload(
        bytes: bytes,
        contentType: mimeType,
      );
    }

    final encryptedFile = await _encryptedMediaHelper.encrypt(bytes);
    return _PreparedMediaUpload(
      bytes: encryptedFile.data,
      contentType: 'application/octet-stream',
      encryptedFile: encryptedFile,
    );
  }

  Map<String, dynamic> _encryptedFileContent(
    EncryptedFile encryptedFile,
    Uri uri, {
    required String mimeType,
  }) {
    return {
      'url': uri.toString(),
      'mimetype': mimeType,
      'v': 'v2',
      'key': {
        'alg': 'A256CTR',
        'ext': true,
        'k': encryptedFile.k,
        'key_ops': ['encrypt', 'decrypt'],
        'kty': 'oct',
      },
      'iv': encryptedFile.iv,
      'hashes': {'sha256': encryptedFile.sha256},
    };
  }

  Future<Uri> _uploadContentWithProgress(
    Uint8List content, {
    String? filename,
    String? contentType,
    void Function(int uploadedBytes, int totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (onProgress == null) {
      return _client.uploadContent(
        content,
        filename: filename,
        contentType: contentType,
      );
    }

    final mediaConfig = await _client.getConfig();
    final maxMediaSize = mediaConfig.mUploadSize;
    if (maxMediaSize != null && maxMediaSize < content.lengthInBytes) {
      throw FileTooBigMatrixException(content.lengthInBytes, maxMediaSize);
    }

    final token = accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Missing Matrix access token');
    }

    final uploadUri = Uri.parse(homeserverUrl).resolveUri(
      Uri(
        path: '/_matrix/media/v3/upload',
        queryParameters: {
          if (filename != null && filename.isNotEmpty) 'filename': filename,
        },
      ),
    );

    final client = io.HttpClient();
    try {
      _throwIfCancelled(isCancelled);
      final request = await client.postUrl(uploadUri);
      request.contentLength = content.lengthInBytes;
      request.headers.set(io.HttpHeaders.authorizationHeader, 'Bearer $token');
      if (contentType != null && contentType.isNotEmpty) {
        request.headers.set(io.HttpHeaders.contentTypeHeader, contentType);
      }

      const chunkSize = 16 * 1024;
      var uploaded = 0;
      onProgress(0, content.lengthInBytes);

      for (var offset = 0; offset < content.length; offset += chunkSize) {
        _throwIfCancelled(isCancelled);
        final end = (offset + chunkSize).clamp(0, content.length);
        request.add(content.sublist(offset, end));
        await request.flush();
        uploaded = end;
        onProgress(uploaded, content.lengthInBytes);
      }
      _throwIfCancelled(isCancelled);

      final response = await request.close();
      _throwIfCancelled(isCancelled);
      final responseBytes = await consolidateHttpClientResponseBytes(response);
      if (response.statusCode != io.HttpStatus.ok) {
        throw Exception(
          'Upload failed (${response.statusCode}): ${utf8.decode(responseBytes)}',
        );
      }
      final responseJson = jsonDecode(utf8.decode(responseBytes));
      return Uri.parse(responseJson['content_uri'] as String);
    } finally {
      client.close(force: true);
    }
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw const MatrixUploadCancelledException();
    }
  }

  /// Returns the current access token for authenticated requests.
  String? get accessToken => _client.accessToken;

  MatrixMediaHelper get mediaHelper => MatrixMediaHelper(
        homeserverUrl: homeserverUrl,
        accessToken: accessToken,
      );

  /// Resolves Matrix media without exposing the access token in its URL.
  MatrixMediaRequest? getMediaRequest(
    String? mxcUrl, {
    int? width,
    int? height,
  }) {
    return mediaHelper.fromMxc(mxcUrl, width: width, height: height);
  }

  /// Converts an SDK-provided media URL to an authenticated request.
  MatrixMediaRequest getMediaRequestForUrl(Uri url) {
    return mediaHelper.fromUrl(url);
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
