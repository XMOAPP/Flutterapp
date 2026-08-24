import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/invite_link_models.dart';
import '../providers/matrix_provider.dart';
import '../screens/invite/invite_preview_screen.dart';
import '../screens/matrix_chat_screen.dart';
import 'matrix_service.dart';

class InviteLinkException implements Exception {
  const InviteLinkException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class InviteLinkService {
  InviteLinkService._();
  static final InviteLinkService instance = InviteLinkService._();

  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{40,64}$');

  GlobalKey<NavigatorState>? _navigatorKey;
  MatrixProvider? _matrixProvider;
  String? _pendingLink;
  String? _pendingSecureToken;
  Timer? _pendingSecureTokenTimer;
  bool _pendingRetryScheduled = false;
  bool _pendingAuthResumeScheduled = false;
  int _pendingAuthResumeAttempts = 0;
  bool _wasLoggedIn = false;

  Uri get _apiBase => Uri.parse(AppConfig.inviteServerUrl);

  Uri _endpoint(String path) {
    final basePath = _apiBase.path.replaceFirst(RegExp(r'/+$'), '');
    final suffix = path.replaceFirst(RegExp(r'^/+'), '');
    return _apiBase.replace(path: '$basePath/$suffix', query: null);
  }

  void init({
    required GlobalKey<NavigatorState> navigatorKey,
    required MatrixProvider matrixProvider,
  }) {
    _matrixProvider?.removeListener(_handleAuthStateChanged);
    _navigatorKey = navigatorKey;
    _matrixProvider = matrixProvider;
    _wasLoggedIn = matrixProvider.isLoggedIn;
    matrixProvider.addListener(_handleAuthStateChanged);
    _schedulePendingLink();
  }

  void _handleAuthStateChanged() {
    final provider = _matrixProvider;
    if (provider == null) return;
    final isLoggedIn = provider.isLoggedIn;
    if (_wasLoggedIn && !isLoggedIn) {
      _clearPendingSecureInvite();
    }
    _wasLoggedIn = isLoggedIn;
    if (isLoggedIn) _schedulePendingSecureInvite();
  }

  void _rememberPendingSecureInvite(String token) {
    _pendingSecureToken = token;
    _pendingAuthResumeAttempts = 0;
    _pendingSecureTokenTimer?.cancel();
    _pendingSecureTokenTimer = Timer(
      const Duration(minutes: 10),
      _clearPendingSecureInvite,
    );
  }

  void _clearPendingSecureInvite() {
    _pendingSecureToken = null;
    _pendingAuthResumeAttempts = 0;
    _pendingSecureTokenTimer?.cancel();
    _pendingSecureTokenTimer = null;
  }

  void _schedulePendingSecureInvite() {
    if (_pendingSecureToken == null || _pendingAuthResumeScheduled) return;
    _pendingAuthResumeScheduled = true;
    final delay = _pendingAuthResumeAttempts == 0
        ? const Duration(milliseconds: 500)
        : const Duration(milliseconds: 750);
    Future<void>.delayed(delay, () async {
      _pendingAuthResumeScheduled = false;
      final token = _pendingSecureToken;
      final provider = _matrixProvider;
      if (token == null || provider == null || !provider.isLoggedIn) return;
      if (_navigatorKey?.currentState == null ||
          _navigatorKey?.currentContext == null) {
        _pendingAuthResumeAttempts++;
        if (_pendingAuthResumeAttempts < 8) {
          _schedulePendingSecureInvite();
        } else {
          _clearPendingSecureInvite();
        }
        return;
      }
      try {
        await _confirmSecureInvite(token, previewIsOpen: false);
        if (_pendingSecureToken == token) _clearPendingSecureInvite();
      } on InviteLinkException catch (error) {
        _clearPendingSecureInvite();
        _showCurrentMessage(error.message);
      } catch (_) {
        _clearPendingSecureInvite();
        _showCurrentMessage('This invite link is not available.');
      }
    });
  }

  static String? extractSecureToken(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return null;

    String? token;
    if (uri.scheme.toLowerCase() == 'https' &&
        uri.host.toLowerCase() ==
            Uri.parse(AppConfig.inviteWebBaseUrl).host.toLowerCase() &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'join') {
      token = uri.pathSegments[1];
    } else if (uri.scheme.toLowerCase() == 'xmo' &&
        uri.host.toLowerCase() == 'join' &&
        uri.pathSegments.length == 1) {
      token = uri.pathSegments.first;
    }
    return token != null && _tokenPattern.hasMatch(token) ? token : null;
  }

  bool isInviteLink(String link) {
    if (extractSecureToken(link) != null) return true;
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return false;
    return (uri.scheme.toLowerCase() == 'xmo' &&
            uri.host.toLowerCase() == 'join' &&
            MatrixService.extractRoomIdentifier(link) != null) ||
        (uri.host.toLowerCase() == 'matrix.to' &&
            MatrixService.extractRoomIdentifier(link) != null);
  }

  Future<XmoInviteLink> createInvite(
    MatrixService service,
    String roomId, {
    int expiryDays = 30,
    int? maxUses,
  }) async {
    final decoded = await _requestJson(
      'POST',
      '/invites/create',
      service: service,
      body: {
        'roomId': roomId,
        'expiryDays': expiryDays,
        if (maxUses != null) 'maxUses': maxUses,
      },
    );
    final invite = decoded['invite'];
    if (invite is! Map)
      throw const InviteLinkException('Invalid invite response.');
    return XmoInviteLink.fromJson(invite);
  }

  Future<List<XmoInviteLink>> listInvites(
    MatrixService service,
    String roomId,
  ) async {
    final decoded = await _requestJson(
      'POST',
      '/invites/list',
      service: service,
      body: {'roomId': roomId},
    );
    final values = decoded['invites'];
    if (values is! List) return const [];
    return values
        .whereType<Map>()
        .map((value) => XmoInviteLink.fromJson(value))
        .toList(growable: false);
  }

  Future<void> revokeInvite(MatrixService service, String linkId) async {
    await _requestJson(
      'POST',
      '/invites/revoke',
      service: service,
      body: {'linkId': linkId},
    );
  }

  Future<XmoInvitePreview> preview(String token) async {
    final decoded = await _requestJson('GET', '/invites/$token/preview');
    final invite = decoded['invite'];
    if (invite is! Map)
      throw const InviteLinkException('Invalid invite response.');
    return XmoInvitePreview.fromJson(invite);
  }

  Future<XmoInviteRedemption> redeem(
    MatrixService service,
    String token,
  ) async {
    final decoded = await _requestJson(
      'POST',
      '/invites/$token/redeem',
      service: service,
    );
    return XmoInviteRedemption.fromJson(decoded);
  }

  Future<bool> handleLink(String link) async {
    if (!isInviteLink(link)) return false;
    if (_navigatorKey?.currentState == null ||
        _navigatorKey?.currentContext == null) {
      _pendingLink = link;
      _schedulePendingLink();
      return true;
    }

    if (_pendingLink == link) _pendingLink = null;

    final token = extractSecureToken(link);
    if (token != null) {
      await _openSecurePreview(token);
      return true;
    }
    await _openLegacyInvite(link);
    return true;
  }

  void _schedulePendingLink() {
    if (_pendingLink == null || _pendingRetryScheduled) return;
    _pendingRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingRetryScheduled = false;
      final pending = _pendingLink;
      if (pending == null) return;
      if (_navigatorKey?.currentState == null ||
          _navigatorKey?.currentContext == null) {
        _schedulePendingLink();
        return;
      }
      _pendingLink = null;
      unawaited(handleLink(pending));
    });
  }

  Future<void> _openSecurePreview(String token) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    try {
      final invite = await preview(token);
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => InvitePreviewScreen(
            invite: invite,
            onConfirm: () => _confirmSecureInvite(token),
          ),
        ),
      );
    } on InviteLinkException catch (error) {
      _showCurrentMessage(error.message);
    } on FormatException {
      _showCurrentMessage('This invite link is not available.');
    }
  }

  Future<void> _confirmSecureInvite(
    String token, {
    bool previewIsOpen = true,
  }) async {
    final context = _navigatorKey?.currentContext;
    if (context == null)
      throw const InviteLinkException('XMO is not ready yet.');
    final provider = Provider.of<MatrixProvider>(context, listen: false);
    final service = provider.service;
    if (!service.isLoggedIn) {
      _rememberPendingSecureInvite(token);
      _navigatorKey?.currentState?.pop();
      _showCurrentMessage('Log in to continue with this invite.');
      return;
    }

    final redemption = await redeem(service, token);
    var room = service.getRoomById(redemption.roomId);
    if (room?.membership == Membership.join ||
        room?.membership == Membership.invite) {
      await _openRedeemedRoom(room!, provider, replaceCurrent: previewIsOpen);
      return;
    }

    if (redemption.action == 'knock') {
      await service.requestToJoinRoom(redemption.roomId);
      if (previewIsOpen) _navigatorKey?.currentState?.pop();
      _showCurrentMessage('Join request sent. An admin must approve it.');
      return;
    }

    await service.joinRoom(redemption.roomId);
    room = await _waitForRoom(service, redemption.roomId);
    if (room == null) {
      if (previewIsOpen) _navigatorKey?.currentState?.pop();
      _showCurrentMessage('Joined successfully. The chat will appear shortly.');
      return;
    }
    await _openRedeemedRoom(room, provider, replaceCurrent: previewIsOpen);
  }

  Future<Room?> _waitForRoom(MatrixService service, String roomId) async {
    for (final delay in const [0, 250, 500, 900, 1400]) {
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      final room = service.getRoomById(roomId);
      if (room != null && room.membership == Membership.join) return room;
      try {
        await service.client.oneShotSync();
      } catch (_) {}
    }
    return service.getRoomById(roomId);
  }

  Future<void> _openRedeemedRoom(
    Room room,
    MatrixProvider provider, {
    required bool replaceCurrent,
  }) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    final route = MaterialPageRoute(
      builder: (_) => MatrixChatScreen(room: room, matrixProvider: provider),
    );
    if (replaceCurrent) {
      await navigator.pushReplacement(route);
    } else {
      await navigator.push(route);
    }
  }

  Future<void> _openLegacyInvite(String link) async {
    final roomId = MatrixService.extractRoomIdentifier(link);
    final context = _navigatorKey?.currentContext;
    if (roomId == null || context == null) return;
    final provider = Provider.of<MatrixProvider>(context, listen: false);
    final service = provider.service;
    if (!service.isLoggedIn) {
      _showCurrentMessage('Log in to open this invite link.');
      return;
    }
    var room = service.getRoomById(roomId);
    try {
      await service.client.oneShotSync();
      room = service.getRoomById(roomId) ?? room;
    } catch (_) {}
    if (room?.membership == Membership.join ||
        room?.membership == Membership.invite) {
      await _openRedeemedRoom(room!, provider, replaceCurrent: false);
      return;
    }
    try {
      final results = await service.searchPublicRooms(roomId);
      final previewRoom = results.cast<PublicRoomsChunk?>().firstWhere(
        (chunk) => chunk?.roomId == roomId,
        orElse: () => results.isNotEmpty ? results.first : null,
      );
      if (previewRoom != null) {
        await _navigatorKey!.currentState!.push(
          MaterialPageRoute(
            builder: (_) => MatrixChatScreen(
              previewChannel: previewRoom,
              previewIsChannelHint:
                  previewRoom.topic?.contains('xmo_channel') == true,
              matrixProvider: provider,
            ),
          ),
        );
        return;
      }
    } catch (_) {}
    _showCurrentMessage('This invite link is not available.');
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    MatrixService? service,
    Map<String, dynamic>? body,
  }) async {
    final uri = _endpoint(path);
    final headers = <String, String>{'Accept': 'application/json'};
    final token = service?.accessToken;
    if (service != null && (token == null || token.isEmpty)) {
      throw const InviteLinkException(
        'Your XMO session is unavailable. Sign in again.',
      );
    }
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (body != null || method == 'POST')
      headers['Content-Type'] = 'application/json';

    final response = method == 'GET'
        ? await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15))
        : await http
              .post(
                uri,
                headers: headers,
                body: jsonEncode(body ?? const <String, dynamic>{}),
              )
              .timeout(const Duration(seconds: 15));
    Map<String, dynamic> decoded = const {};
    try {
      final value = jsonDecode(response.body);
      if (value is Map) decoded = Map<String, dynamic>.from(value);
    } catch (_) {}
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] == false) {
      final candidate = decoded['error']?.toString().trim();
      throw InviteLinkException(
        candidate != null && candidate.isNotEmpty && candidate.length <= 180
            ? candidate
            : 'Invite service is temporarily unavailable.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  void _showCurrentMessage(String message) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
