import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../screens/matrix_chat_screen.dart';
import 'matrix_service.dart';
import 'voip_service.dart';

class CallLinkService {
  CallLinkService._();
  static final CallLinkService instance = CallLinkService._();

  GlobalKey<NavigatorState>? _navigatorKey;
  Uri? _pendingCallLink;

  void init({required GlobalKey<NavigatorState> navigatorKey}) {
    _navigatorKey = navigatorKey;
    final pending = _pendingCallLink;
    if (pending != null) {
      _pendingCallLink = null;
      unawaited(handleLink(pending.toString()));
    }
  }

  bool isCallLink(String link) => _roomIdFromLink(link) != null;

  Future<bool> handleLink(String link) async {
    final roomId = _roomIdFromLink(link);
    if (roomId == null) return false;

    if (_navigatorKey?.currentState == null ||
        _navigatorKey?.currentContext == null) {
      _pendingCallLink = Uri.tryParse(link);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(handleLink(link));
      });
      return true;
    }

    final matrixService = MatrixService();
    if (!matrixService.isLoggedIn) {
      _showCurrentMessage('Log in to open this call link.');
      return true;
    }

    Room? room = matrixService.getRoomById(roomId);
    try {
      await matrixService.client.oneShotSync();
      room = matrixService.getRoomById(roomId) ?? room;
    } catch (e) {
      debugPrint('[CallLinkService] Sync before opening call link failed: $e');
    }

    if (_navigatorKey?.currentState == null ||
        _navigatorKey?.currentContext == null) {
      _pendingCallLink = Uri.tryParse(link);
      return true;
    }

    if (room == null) {
      _showCurrentMessage('This call link is not available on this device.');
      return true;
    }

    final groupCall = VoipService().ongoingGroupCallForRoom(room);
    if (groupCall != null) {
      try {
        await VoipService().answerIncomingGroupCall(groupCall);
      } catch (e) {
        _showCurrentMessage('Unable to join call: $e');
      }
      return true;
    }

    await _openRoom(room);
    _showCurrentMessage('No active group call to join.');
    return true;
  }

  Future<void> _openRoom(Room room) async {
    final navigator = _navigatorKey?.currentState;
    final context = _navigatorKey?.currentContext;
    if (navigator == null || context == null) return;
    final provider = Provider.of<MatrixProvider>(context, listen: false);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => MatrixChatScreen(
          room: room,
          matrixProvider: provider,
        ),
      ),
    );
  }

  String? _roomIdFromLink(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;

    if (uri.scheme == 'xmo' && uri.host == 'call') {
      final queryRoomId = uri.queryParameters['room_id']?.trim();
      if (queryRoomId != null && queryRoomId.isNotEmpty) return queryRoomId;
      if (uri.pathSegments.isNotEmpty) return uri.pathSegments.first;
      return null;
    }

    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'xmo.dpdns.org' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'call') {
      final queryRoomId = uri.queryParameters['room_id']?.trim();
      if (queryRoomId != null && queryRoomId.isNotEmpty) return queryRoomId;
      if (uri.pathSegments.length > 1) return uri.pathSegments[1];
    }

    return null;
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showCurrentMessage(String message) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    _showMessage(context, message);
  }
}
