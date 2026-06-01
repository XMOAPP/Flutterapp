import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as rtc;

import '../screens/direct_chat/direct_call_screen.dart';
import '../screens/group/group_call_screen.dart';
import 'call_history_service.dart';
import 'matrix_service.dart';

class VoipService {
  static final VoipService _instance = VoipService._internal();
  factory VoipService() => _instance;
  VoipService._internal();

  VoIP? _voip;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _openingCallScreen = false;
  int _fullscreenIncomingCallScopeDepth = 0;

  // ── Active call tracking ─────────────────────────────────────────────────
  CallSession? _activeSession;
  GroupCall? _activeGroupCall;
  DateTime? _callConnectedAt;
  DateTime? _groupCallConnectedAt;
  CallHistoryDirection? _activeGroupCallDirection;
  StreamSubscription? _activeSessionStateSub;
  StreamSubscription? _activeGroupCallStateSub;
  final Set<String> _ownedGroupCallIds = <String>{};
  final Set<String> _rejectedGroupCallIds = <String>{};

  /// Whether the call is currently in picture-in-picture mode.
  final ValueNotifier<bool> pipMode = ValueNotifier(false);
  final ValueNotifier<int> fullscreenCallRouteDepth = ValueNotifier(0);
  final ValueNotifier<CallSession?> incomingCall = ValueNotifier(null);
  final ValueNotifier<GroupCall?> incomingGroupCall = ValueNotifier(null);
  final ValueNotifier<int> callStateVersion = ValueNotifier(0);

  CallSession? get activeSession => _activeSession;
  GroupCall? get activeGroupCall => _activeGroupCall;
  DateTime? get callConnectedAt => _callConnectedAt;
  DateTime? get groupCallConnectedAt => _groupCallConnectedAt;
  bool get isInCall => _activeSession != null || _activeGroupCall != null;
  bool get shouldOpenIncomingCallsFullscreen =>
      _fullscreenIncomingCallScopeDepth > 0;
  bool get isFullscreenCallRouteVisible => fullscreenCallRouteDepth.value > 0;

  bool get isInitialized => _voip != null;

  void enterFullscreenCallRoute() {
    fullscreenCallRouteDepth.value++;
  }

  void exitFullscreenCallRoute() {
    if (fullscreenCallRouteDepth.value == 0) return;
    fullscreenCallRouteDepth.value--;
  }

  void enterFullscreenIncomingCallScope() {
    _fullscreenIncomingCallScopeDepth++;
  }

  void exitFullscreenIncomingCallScope() {
    if (_fullscreenIncomingCallScopeDepth == 0) return;
    _fullscreenIncomingCallScopeDepth--;
  }

  void _notifyCallStateChanged() {
    callStateVersion.value++;
  }

  bool canEndGroupCall(GroupCall groupCall) {
    return _ownedGroupCallIds.contains(groupCall.groupCallId);
  }

  bool isGroupCallRejected(GroupCall groupCall) {
    return _rejectedGroupCallIds.contains(groupCall.groupCallId);
  }

  Future<void> leaveOrEndGroupCall(GroupCall groupCall) async {
    final shouldEnd = canEndGroupCall(groupCall);
    if (shouldEnd) {
      await groupCall.terminate();
      _ownedGroupCallIds.remove(groupCall.groupCallId);
    } else {
      await groupCall.leave();
    }
    if (_activeGroupCall == groupCall) {
      _cleanupGroupCall();
    } else {
      pipMode.value = false;
      _notifyCallStateChanged();
    }
  }

  GroupCall? ongoingGroupCallForRoom(Room room) {
    final groupCall = _voip?.getGroupCallForRoom(room.id);
    if (groupCall == null || groupCall.terminated) return null;
    return groupCall;
  }

  bool isCallStartBlocked(Room room) {
    if (isInCall) return true;
    return !MatrixService().isDirectRoom(room) &&
        ongoingGroupCallForRoom(room) != null;
  }

  void init({
    required MatrixService matrixService,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    _navigatorKey = navigatorKey;
    _voip ??= VoIP(
      matrixService.client,
      _XmoWebRTCDelegate(
        onNewCall: _openCallScreen,
        onNewGroupCall: _openGroupCallScreen,
      ),
    );
  }

  Future<void> startCall(Room room, {required bool video}) async {
    final voip = _voip;
    if (voip == null) {
      throw StateError('VoIP is not initialized');
    }
    if (isInCall) {
      throw StateError('You are already in a call');
    }
    if (!_supportsRoomCall(room)) {
      throw StateError('Calls are only available in direct chats and groups');
    }
    if (!MatrixService().isDirectRoom(room)) {
      await startGroupCall(room, video: video);
      return;
    }
    unawaited(
      CallHistoryService().recordRoomCall(
        room: room,
        kind: CallHistoryKind.direct,
        direction: CallHistoryDirection.outgoing,
        status: CallHistoryStatus.answered,
        video: video,
      ),
    );
    await voip.inviteToCall(room.id, video ? CallType.kVideo : CallType.kVoice);
  }

  Future<void> startGroupCall(Room room, {required bool video}) async {
    final voip = _voip;
    if (voip == null) {
      throw StateError('VoIP is not initialized');
    }
    if (!_supportsRoomCall(room) || MatrixService().isDirectRoom(room)) {
      throw StateError('Group calls are only available in groups');
    }
    var groupCall = voip.getGroupCallForRoom(room.id);
    if (!room.groupCallsEnabled) {
      await room.enableGroupCalls();
    }

    if (!room.canJoinGroupCall && !room.canCreateGroupCall) {
      throw StateError(
        'Group calls are not enabled for this room. Ask an admin to enable them.',
      );
    }

    var createdGroupCall = false;
    if (groupCall != null && !groupCall.terminated) {
      throw StateError('A group call is already ongoing. Use Join.');
    }

    if (groupCall == null || groupCall.terminated) {
      if (!room.canCreateGroupCall) {
        throw StateError(
            'You do not have permission to start group calls here');
      }
      groupCall = await voip.newGroupCall(
        room.id,
        video ? GroupCallType.Video : GroupCallType.Voice,
        GroupCallIntent.Prompt,
      );
      createdGroupCall = groupCall != null;
    }
    if (groupCall == null) {
      throw StateError('Unable to create or join the group call');
    }
    if (createdGroupCall) {
      _ownedGroupCallIds.add(groupCall.groupCallId);
    }

    _trackGroupCall(groupCall, direction: CallHistoryDirection.outgoing);
    unawaited(
      CallHistoryService().recordGroupCall(
        groupCall,
        direction: CallHistoryDirection.outgoing,
        status: CallHistoryStatus.answered,
      ),
    );
    incomingGroupCall.value = null;
    _rejectedGroupCallIds.remove(groupCall.groupCallId);
    if (_needsGroupCallEnter(groupCall)) {
      await _enterGroupCall(groupCall);
    }
    await _pushGroupCallScreen(groupCall);
  }

  bool _supportsRoomCall(Room room) {
    final matrixService = MatrixService();
    if (matrixService.isDirectRoom(room)) return true;
    if (matrixService.isKnownChannel(room.id)) return false;

    final kind = MatrixService.classifyRoomKind(
      typeContent: room.getState(MatrixService.roomTypeStateType)?.content,
      powerLevelsContent: room.getState(EventTypes.RoomPowerLevels)?.content,
      isDirectChat: room.isDirectChat,
      useGroupFallback: true,
    );

    return kind == XmoRoomKind.group || matrixService.isKnownGroup(room.id);
  }

  // ── Session lifecycle ────────────────────────────────────────────────────

  void _trackSession(CallSession session, {bool showIncomingBanner = true}) {
    if (session.isGroupCall) return;
    _activeSession = session;
    _callConnectedAt = null;
    if (session.direction == CallDirection.kIncoming && showIncomingBanner) {
      incomingCall.value = session;
    }
    _notifyCallStateChanged();
    _activeSessionStateSub?.cancel();
    _activeSessionStateSub = session.onCallStateChanged.stream.listen((state) {
      if (state == CallState.kConnected && _callConnectedAt == null) {
        _callConnectedAt = DateTime.now();
        if (incomingCall.value == session) {
          incomingCall.value = null;
        }
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
    incomingCall.value = null;
    _notifyCallStateChanged();
  }

  void _trackGroupCall(
    GroupCall groupCall, {
    CallHistoryDirection? direction,
  }) {
    _activeGroupCall = groupCall;
    _activeGroupCallDirection = direction ?? _activeGroupCallDirection;
    if (_groupCallConnectedAt == null && _hasConnectedGroupPeer(groupCall)) {
      _groupCallConnectedAt = DateTime.now();
    }
    _notifyCallStateChanged();
    _activeGroupCallStateSub?.cancel();
    _activeGroupCallStateSub =
        groupCall.onGroupCallState.stream.listen((state) {
      if (state == GroupCallState.Entered &&
          _groupCallConnectedAt == null &&
          _hasConnectedGroupPeer(groupCall)) {
        _groupCallConnectedAt = DateTime.now();
      }
      if (state == GroupCallState.Ended) {
        if (_activeGroupCall == groupCall) {
          _cleanupGroupCall();
        }
      }
    });
    groupCall.onStreamAdd.stream.listen((_) {
      if (_activeGroupCall == groupCall &&
          _groupCallConnectedAt == null &&
          _hasConnectedGroupPeer(groupCall)) {
        _groupCallConnectedAt = DateTime.now();
      }
    });
  }

  bool _hasConnectedGroupPeer(GroupCall groupCall) {
    return groupCall.userMediaStreams.any((stream) => !stream.isLocal()) ||
        groupCall.participants
            .any((user) => user.id != groupCall.room.client.userID);
  }

  void _cleanupGroupCall() {
    _activeGroupCallStateSub?.cancel();
    _activeGroupCallStateSub = null;
    _activeGroupCall = null;
    _groupCallConnectedAt = null;
    _activeGroupCallDirection = null;
    pipMode.value = false;
    incomingGroupCall.value = null;
    _notifyCallStateChanged();
  }

  // ── PiP minimize / maximize ──────────────────────────────────────────────

  /// Minimizes the current call to a floating PiP overlay.
  /// Call this from DirectCallScreen after Navigator.pop().
  void minimizeCall() {
    if (_activeSession == null && _activeGroupCall == null) return;
    pipMode.value = true;
  }

  /// Restores the PiP overlay back to full-screen call.
  void maximizeCall() {
    final session = _activeSession;
    final groupCall = _activeGroupCall;
    pipMode.value = false;
    if (groupCall != null) {
      _pushGroupCallScreen(groupCall);
      return;
    }
    if (session == null) return;
    _pushCallScreen(session);
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  Future<void> _openCallScreen(CallSession session) async {
    if (session.isGroupCall) return;
    if (!_supportsRoomCall(session.room)) {
      await session.reject();
      return;
    }
    if (_openingCallScreen) return;
    final openFullscreen = shouldOpenIncomingCallsFullscreen;
    _trackSession(session, showIncomingBanner: !openFullscreen);
    if (session.direction == CallDirection.kIncoming && !openFullscreen) {
      return;
    }
    await _pushCallScreen(session);
  }

  Future<void> _openGroupCallScreen(GroupCall groupCall) async {
    if (!_supportsRoomCall(groupCall.room)) {
      await groupCall.terminate();
      return;
    }
    if (groupCall.state != GroupCallState.Entered) {
      incomingGroupCall.value = groupCall;
      _notifyCallStateChanged();
      return;
    }
    _trackGroupCall(groupCall);
    incomingGroupCall.value = null;
    await _pushGroupCallScreen(groupCall);
  }

  Future<void> answerIncomingCall(CallSession session) async {
    if (_activeSession != session) {
      _trackSession(session);
    }
    incomingCall.value = null;
    await session.answer();
    unawaited(
      CallHistoryService().recordDirectCall(
        session,
        direction: CallHistoryDirection.incoming,
        status: CallHistoryStatus.answered,
      ),
    );
    await _pushCallScreen(session);
  }

  Future<void> rejectIncomingCall(CallSession session) async {
    incomingCall.value = null;
    unawaited(
      CallHistoryService().recordDirectCall(
        session,
        direction: CallHistoryDirection.incoming,
        status: CallHistoryStatus.rejected,
      ),
    );
    await session.reject();
    if (_activeSession == session) {
      _cleanupSession();
    }
  }

  Future<void> answerIncomingGroupCall(GroupCall groupCall) async {
    if (_activeGroupCall == groupCall) {
      incomingGroupCall.value = null;
      if (_needsGroupCallEnter(groupCall)) {
        await _enterGroupCall(groupCall);
      }
      await _pushGroupCallScreen(groupCall);
      return;
    }
    if (isInCall) {
      throw StateError('You are already in a call');
    }
    incomingGroupCall.value = null;
    _rejectedGroupCallIds.remove(groupCall.groupCallId);
    _trackGroupCall(groupCall, direction: CallHistoryDirection.incoming);
    unawaited(
      CallHistoryService().recordGroupCall(
        groupCall,
        direction: CallHistoryDirection.incoming,
        status: CallHistoryStatus.answered,
      ),
    );
    if (_needsGroupCallEnter(groupCall)) {
      await _enterGroupCall(groupCall);
    }
    await _pushGroupCallScreen(groupCall);
  }

  bool _needsGroupCallEnter(GroupCall groupCall) {
    return groupCall.state != GroupCallState.Entered ||
        groupCall.localUserMediaStream?.stream == null;
  }

  Future<void> _enterGroupCall(GroupCall groupCall) async {
    try {
      await groupCall.enter();
    } catch (e) {
      if (!_isNullMediaStreamCast(e)) rethrow;

      debugPrint(
        '[VOIP] Group call media init failed; retrying with audio only: $e',
      );
      final fallbackStream = await _createAudioOnlyGroupStream(groupCall);
      await groupCall.enter(stream: fallbackStream);
    }
  }

  bool _isNullMediaStreamCast(Object error) {
    final message = error.toString();
    return message.contains('Null') && message.contains('MediaStream');
  }

  Future<WrappedMediaStream> _createAudioOnlyGroupStream(
    GroupCall groupCall,
  ) async {
    final voip = _voip;
    if (voip == null) {
      throw StateError('VoIP is not initialized');
    }

    try {
      final stream = await voip.delegate.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      final userId = groupCall.room.client.userID;
      if (userId == null) {
        throw StateError('User is not logged in');
      }

      return WrappedMediaStream(
        renderer: voip.delegate.createRenderer(),
        stream: stream,
        userId: userId,
        room: groupCall.room,
        client: groupCall.room.client,
        purpose: SDPStreamMetadataPurpose.Usermedia,
        audioMuted: stream.getAudioTracks().isEmpty,
        videoMuted: true,
        isWeb: voip.delegate.isWeb,
        isGroupCall: true,
      );
    } catch (e) {
      throw StateError(
        'Unable to access microphone or camera. Check app permissions and try again. ($e)',
      );
    }
  }

  void dismissIncomingGroupCall(GroupCall groupCall) {
    rejectGroupCall(groupCall);
  }

  void rejectGroupCall(GroupCall groupCall) {
    _rejectedGroupCallIds.add(groupCall.groupCallId);
    if (incomingGroupCall.value == groupCall) {
      incomingGroupCall.value = null;
    }
    _notifyCallStateChanged();
    unawaited(
      CallHistoryService().recordGroupCall(
        groupCall,
        direction: CallHistoryDirection.incoming,
        status: CallHistoryStatus.rejected,
      ),
    );
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

  Future<void> _pushGroupCallScreen(GroupCall groupCall) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    if (_openingCallScreen) return;

    _openingCallScreen = true;
    try {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(groupCall: groupCall),
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
  final Future<void> Function(GroupCall groupCall) onNewGroupCall;

  _XmoWebRTCDelegate({
    required this.onNewCall,
    required this.onNewGroupCall,
  });

  @override
  rtc.MediaDevices get mediaDevices => webrtc.navigator.mediaDevices;

  @override
  Future<rtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) {
    final normalizedConfiguration = Map<String, dynamic>.from(configuration);
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
    normalizedConfiguration.putIfAbsent('iceCandidatePoolSize', () => 10);
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
    }).toList();
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
  Future<void> handleMissedCall(CallSession session) {
    return CallHistoryService().recordDirectCall(
      session,
      direction: CallHistoryDirection.incoming,
      status: CallHistoryStatus.missed,
    );
  }

  @override
  Future<void> handleNewGroupCall(GroupCall groupCall) async {
    VoipService()._notifyCallStateChanged();
    await onNewGroupCall(groupCall);
  }

  @override
  Future<void> handleGroupCallEnded(GroupCall groupCall) async {
    VoipService()._ownedGroupCallIds.remove(groupCall.groupCallId);
    VoipService()._rejectedGroupCallIds.remove(groupCall.groupCallId);
    if (VoipService().activeGroupCall == groupCall) {
      VoipService()._cleanupGroupCall();
    } else {
      VoipService()._notifyCallStateChanged();
    }
  }
}
