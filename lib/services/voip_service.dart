import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as rtc;

import '../screens/direct_chat/direct_call_screen.dart';
import 'matrix_service.dart';

class VoipService {
  static final VoipService _instance = VoipService._internal();
  factory VoipService() => _instance;
  VoipService._internal();

  VoIP? _voip;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _openingCallScreen = false;

  // ── Active call tracking ─────────────────────────────────────────────────
  CallSession? _activeSession;
  DateTime? _callConnectedAt;
  StreamSubscription? _activeSessionStateSub;

  /// Whether the call is currently in picture-in-picture mode.
  final ValueNotifier<bool> pipMode = ValueNotifier(false);

  CallSession? get activeSession => _activeSession;
  DateTime? get callConnectedAt => _callConnectedAt;
  bool get isInCall => _activeSession != null;

  bool get isInitialized => _voip != null;

  void init({
    required MatrixService matrixService,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    _navigatorKey = navigatorKey;
    _voip ??= VoIP(
      matrixService.client,
      _XmoWebRTCDelegate(onNewCall: _openCallScreen),
    );
  }

  Future<void> startCall(Room room, {required bool video}) async {
    final voip = _voip;
    if (voip == null) {
      throw StateError('VoIP is not initialized');
    }
    if (!MatrixService().isDirectRoom(room)) {
      throw StateError('Calls are only available in direct chats');
    }
    await voip.inviteToCall(room.id, video ? CallType.kVideo : CallType.kVoice);
  }

  // ── Session lifecycle ────────────────────────────────────────────────────

  void _trackSession(CallSession session) {
    _activeSession = session;
    _callConnectedAt = null;
    _activeSessionStateSub?.cancel();
    _activeSessionStateSub =
        session.onCallStateChanged.stream.listen((state) {
      if (state == CallState.kConnected && _callConnectedAt == null) {
        _callConnectedAt = DateTime.now();
      }
      if (state == CallState.kEnded) {
        _cleanupSession();
      }
    });
  }

  void _cleanupSession() {
    _activeSessionStateSub?.cancel();
    _activeSessionStateSub = null;
    _activeSession = null;
    _callConnectedAt = null;
    pipMode.value = false;
  }

  // ── PiP minimize / maximize ──────────────────────────────────────────────

  /// Minimizes the current call to a floating PiP overlay.
  /// Call this from DirectCallScreen after Navigator.pop().
  void minimizeCall() {
    if (_activeSession == null) return;
    pipMode.value = true;
  }

  /// Restores the PiP overlay back to full-screen call.
  void maximizeCall() {
    final session = _activeSession;
    if (session == null) return;
    pipMode.value = false;
    _pushCallScreen(session);
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  Future<void> _openCallScreen(CallSession session) async {
    if (!MatrixService().isDirectRoom(session.room)) {
      await session.reject();
      return;
    }
    if (_openingCallScreen) return;
    _trackSession(session);
    await _pushCallScreen(session);
  }

  Future<void> _pushCallScreen(CallSession session) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    if (_openingCallScreen) return;

    _openingCallScreen = true;
    try {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => DirectCallScreen(session: session),
          fullscreenDialog: true,
        ),
      );
    } finally {
      _openingCallScreen = false;
    }
  }
}

class _XmoWebRTCDelegate implements WebRTCDelegate {
  final Future<void> Function(CallSession session) onNewCall;

  _XmoWebRTCDelegate({required this.onNewCall});

  @override
  rtc.MediaDevices get mediaDevices => webrtc.navigator.mediaDevices;

  @override
  Future<rtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) {
    final normalizedConfiguration =
        Map<String, dynamic>.from(configuration);
    final iceServers = _normalizeIceServers(
      normalizedConfiguration['iceServers'],
    );

    if (iceServers.isEmpty) {
      debugPrint(
        '[VOIP] Homeserver did not provide TURN/STUN servers; using public STUN fallback. Configure coturn on the homeserver for reliable calls.',
      );
      iceServers.addAll(_fallbackStunServers);
    }

    normalizedConfiguration['iceServers'] = iceServers;
    debugPrint('[VOIP] ICE servers configured: ${iceServers.length}');

    return webrtc.createPeerConnection(
      normalizedConfiguration,
      constraints,
    );
  }

  static const List<Map<String, dynamic>> _fallbackStunServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  List<Map<String, dynamic>> _normalizeIceServers(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];

    return value
        .whereType<Map>()
        .map((server) => Map<String, dynamic>.from(server))
        .where((server) {
          final urls = server['urls'] ?? server['url'];
          if (urls is String) {
            return urls.trim().isNotEmpty;
          }
          if (urls is List) {
            return urls.whereType<String>().any(
                  (url) => url.trim().isNotEmpty,
                );
          }
          return false;
        })
        .toList();
  }

  @override
  rtc.VideoRenderer createRenderer() => webrtc.RTCVideoRenderer();

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get canHandleNewCall => true;

  @override
  Future<void> playRingtone() async {}

  @override
  Future<void> stopRingtone() async {}

  @override
  Future<void> handleNewCall(CallSession session) => onNewCall(session);

  @override
  Future<void> handleCallEnded(CallSession session) async {}

  @override
  Future<void> handleMissedCall(CallSession session) async {}

  @override
  Future<void> handleNewGroupCall(GroupCall groupCall) async {}

  @override
  Future<void> handleGroupCallEnded(GroupCall groupCall) async {}
}
