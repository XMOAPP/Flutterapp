// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as rtc;

import '../screens/direct_chat/direct_call_screen.dart';
import '../screens/group/group_call_screen.dart';
import '../screens/group/incoming_group_call_screen.dart';
import 'call_history_service.dart';
import 'matrix_service.dart';
import 'room_controls_service.dart';

enum CallRecoveryStatus { connected, reconnecting, reconnected, failed }

class VoipService with WidgetsBindingObserver {
  static final VoipService _instance = VoipService._internal();
  factory VoipService() => _instance;
  VoipService._internal();

  VoIP? _voip;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _openingCallScreen = false;
  int _fullscreenIncomingCallScopeDepth = 0;
  final Map<String, int> _fullscreenIncomingGroupRoomScopes = <String, int>{};
  AudioPlayer? _ringtonePlayer;
  bool _ringtoneStarting = false;
  bool _observingLifecycle = false;
  bool _handlingNativeAction = false;
  DateTime? _lastNativeActionSyncAttempt;
  Timer? _recoveryTimeout;

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
  final Set<String> _locallyClosedGroupCallIds = <String>{};

  /// Whether the call is currently in picture-in-picture mode.
  final ValueNotifier<bool> pipMode = ValueNotifier(false);
  final ValueNotifier<int> fullscreenCallRouteDepth = ValueNotifier(0);
  final ValueNotifier<CallSession?> incomingCall = ValueNotifier(null);
  final ValueNotifier<GroupCall?> incomingGroupCall = ValueNotifier(null);
  final ValueNotifier<int> callStateVersion = ValueNotifier(0);
  final ValueNotifier<CallRecoveryStatus> recoveryStatus =
      ValueNotifier(CallRecoveryStatus.connected);

  CallSession? get activeSession => _activeSession;
  GroupCall? get activeGroupCall => _activeGroupCall;
  DateTime? get callConnectedAt => _callConnectedAt;
  DateTime? get groupCallConnectedAt => _groupCallConnectedAt;
  bool get isInCall => _activeSession != null || _activeGroupCall != null;
  String groupCallLink(Room room) =>
      'https://xmo.dpdns.org/call/${Uri.encodeComponent(room.id)}';
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

  void enterFullscreenIncomingCallScope({String? roomId}) {
    _fullscreenIncomingCallScopeDepth++;
    if (roomId != null && roomId.isNotEmpty) {
      _fullscreenIncomingGroupRoomScopes.update(
        roomId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  void exitFullscreenIncomingCallScope({String? roomId}) {
    if (_fullscreenIncomingCallScopeDepth == 0) return;
    _fullscreenIncomingCallScopeDepth--;
    if (roomId != null && roomId.isNotEmpty) {
      final count = _fullscreenIncomingGroupRoomScopes[roomId];
      if (count == null || count <= 1) {
        _fullscreenIncomingGroupRoomScopes.remove(roomId);
      } else {
        _fullscreenIncomingGroupRoomScopes[roomId] = count - 1;
      }
    }
  }

  bool _shouldOpenIncomingGroupCallFullscreen(Room room) {
    return (_fullscreenIncomingGroupRoomScopes[room.id] ?? 0) > 0;
  }

  void _notifyCallStateChanged() {
    callStateVersion.value++;
  }

  bool canEndGroupCall(GroupCall groupCall) {
    return _ownedGroupCallIds.contains(groupCall.groupCallId);
  }

  bool _isActiveGroupCall(GroupCall groupCall) {
    return _activeGroupCall?.groupCallId == groupCall.groupCallId;
  }

  bool isGroupCallRejected(GroupCall groupCall) {
    return _rejectedGroupCallIds.contains(groupCall.groupCallId);
  }

  static const AndroidAudioAttributes _ringtoneAudioAttributes =
      AndroidAudioAttributes(
    contentType: AndroidAudioContentType.music,
    usage: AndroidAudioUsage.media,
  );

  Future<void> _startRingtone() async {
    if (_ringtoneStarting || _ringtonePlayer?.playing == true) return;
    _ringtoneStarting = true;
    try {
      await _prepareRingtoneAudioRoute();
      final player = _ringtonePlayer ??= AudioPlayer();
      await player.setAndroidAudioAttributes(_ringtoneAudioAttributes);
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(5.0);
      try {
        await player.setAsset('assets/images/Tin Cup Banjo.mp3');
      } catch (e) {
        debugPrint('[VoipService] Failed to load ringtone asset: $e');
        await player.setAudioSource(_RingtoneAudioSource(_buildRingtoneWav()));
      }
      unawaited(
        player.play().catchError((Object e) {
          debugPrint('[VoipService] Failed while playing ringtone: $e');
        }),
      );
      unawaited(_keepRingtoneOnSpeaker());
    } catch (e) {
      debugPrint('[VoipService] Failed to start ringtone: $e');
    } finally {
      _ringtoneStarting = false;
    }
  }

  Future<void> _prepareRingtoneAudioRoute() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(
        true,
        androidAudioAttributes: _ringtoneAudioAttributes,
      );
    } catch (e) {
      debugPrint(
          '[VoipService] Failed to configure ringtone audio session: $e');
    }
    try {
      await AndroidAudioManager().setMode(AndroidAudioHardwareMode.normal);
    } catch (e) {
      debugPrint('[VoipService] Failed to set ringtone audio mode: $e');
    }
    await _routeRingtoneToSpeaker();
  }

  Future<void> _routeRingtoneToSpeaker() async {
    try {
      await webrtc.Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint('[VoipService] Failed to route ringtone to speaker: $e');
    }
  }

  Future<void> _keepRingtoneOnSpeaker() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (_ringtonePlayer?.playing != true) return;
    await _routeRingtoneToSpeaker();
    await Future.delayed(const Duration(milliseconds: 180));
    if (_ringtonePlayer?.playing != true) return;
    await _routeRingtoneToSpeaker();
  }

  Future<void> _stopRingtone() async {
    final player = _ringtonePlayer;
    if (player == null) return;
    try {
      await player.stop();
    } catch (e) {
      debugPrint('[VoipService] Failed to stop ringtone: $e');
    }
  }

  Future<void> leaveOrEndGroupCall(GroupCall groupCall) async {
    final shouldEnd = canEndGroupCall(groupCall);
    _locallyClosedGroupCallIds.add(groupCall.groupCallId);
    if (shouldEnd) {
      await groupCall.terminate();
      _ownedGroupCallIds.remove(groupCall.groupCallId);
    } else {
      await groupCall.leave();
    }
    if (_isActiveGroupCall(groupCall)) {
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
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    _voip ??= VoIP(
      matrixService.client,
      _XmoWebRTCDelegate(
        onNewCall: _openCallScreen,
        onNewGroupCall: _openGroupCallScreen,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverActiveCall(reason: 'app resumed'));
      return;
    }
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        isInCall) {
      _setRecoveryStatus(CallRecoveryStatus.reconnecting);
    }
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
    _setRecoveryStatus(CallRecoveryStatus.connected);
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
    if (!RoomControlsService.canPerform(
      room,
      room.client.userID,
      XmoRoomPermission.startCalls,
    )) {
      throw StateError('You do not have permission to start calls here');
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
      unawaited(
        MatrixService().sendGroupCallPushMarker(
          room: room,
          groupCallId: groupCall.groupCallId,
          video: video,
        ),
      );
    }
    _locallyClosedGroupCallIds.remove(groupCall.groupCallId);

    _setRecoveryStatus(CallRecoveryStatus.connected);
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

  void _trackSession(
    CallSession session, {
    bool showIncomingBanner = true,
    bool playRingtone = true,
  }) {
    if (session.isGroupCall) return;
    _activeSession = session;
    _callConnectedAt = null;
    _setRecoveryStatus(CallRecoveryStatus.connected);
    if (session.direction == CallDirection.kIncoming) {
      if (playRingtone && session.state == CallState.kRinging) {
        unawaited(_startRingtone());
      }
      if (showIncomingBanner) {
        incomingCall.value = session;
      }
    }
    _notifyCallStateChanged();
    _activeSessionStateSub?.cancel();
    _activeSessionStateSub = session.onCallStateChanged.stream.listen((state) {
      if (state == CallState.kConnected && _callConnectedAt == null) {
        _callConnectedAt = DateTime.now();
        unawaited(_stopRingtone());
        if (session.type == CallType.kVoice) {
          unawaited(_routeDirectVoiceCallToEarpiece());
        }
        _setRecoveryStatus(CallRecoveryStatus.connected);
        if (incomingCall.value == session) {
          incomingCall.value = null;
        }
      }
      if (state == CallState.kEnded) {
        unawaited(_stopRingtone());
        _cleanupSession();
      }
    });
  }

  void _cleanupSession() {
    unawaited(_stopRingtone());
    _activeSessionStateSub?.cancel();
    _activeSessionStateSub = null;
    _activeSession = null;
    _callConnectedAt = null;
    pipMode.value = false;
    incomingCall.value = null;
    _setRecoveryStatus(CallRecoveryStatus.connected);
    _notifyCallStateChanged();
  }

  void _trackGroupCall(
    GroupCall groupCall, {
    CallHistoryDirection? direction,
  }) {
    _activeGroupCall = groupCall;
    _activeGroupCallDirection = direction ?? _activeGroupCallDirection;
    _setRecoveryStatus(CallRecoveryStatus.connected);
    if (_groupCallConnectedAt == null && _hasConnectedGroupPeer(groupCall)) {
      _groupCallConnectedAt = DateTime.now();
      _setRecoveryStatus(CallRecoveryStatus.connected);
    }
    _notifyCallStateChanged();
    _activeGroupCallStateSub?.cancel();
    _activeGroupCallStateSub =
        groupCall.onGroupCallState.stream.listen((state) {
      if (state == GroupCallState.Entered &&
          _groupCallConnectedAt == null &&
          _hasConnectedGroupPeer(groupCall)) {
        _groupCallConnectedAt = DateTime.now();
        _setRecoveryStatus(CallRecoveryStatus.connected);
      }
      if (state == GroupCallState.Ended) {
        if (_isActiveGroupCall(groupCall)) {
          _cleanupGroupCall();
        }
      }
    });
    groupCall.onStreamAdd.stream.listen((_) {
      if (_isActiveGroupCall(groupCall) &&
          _groupCallConnectedAt == null &&
          _hasConnectedGroupPeer(groupCall)) {
        _groupCallConnectedAt = DateTime.now();
        _setRecoveryStatus(CallRecoveryStatus.connected);
      }
    });
  }

  bool _hasConnectedGroupPeer(GroupCall groupCall) {
    return groupCall.userMediaStreams.any((stream) => !stream.isLocal()) ||
        groupCall.participants
            .any((user) => user.id != groupCall.room.client.userID);
  }

  void _cleanupGroupCall() {
    unawaited(_stopRingtone());
    _activeGroupCallStateSub?.cancel();
    _activeGroupCallStateSub = null;
    _activeGroupCall = null;
    _groupCallConnectedAt = null;
    _activeGroupCallDirection = null;
    pipMode.value = false;
    incomingGroupCall.value = null;
    _setRecoveryStatus(CallRecoveryStatus.connected);
    _notifyCallStateChanged();
  }

  // ── PiP minimize / maximize ──────────────────────────────────────────────

  /// Minimizes the current call to a floating PiP overlay.
  /// Call this from DirectCallScreen after Navigator.pop().
  void minimizeCall() {
    if (_activeSession == null && _activeGroupCall == null) return;
    pipMode.value = true;
  }

  void ensurePipVisibleAfterCallRouteClosed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!pipMode.value ||
          (_activeSession == null && _activeGroupCall == null)) {
        return;
      }
      if (fullscreenCallRouteDepth.value > 0) {
        fullscreenCallRouteDepth.value = 0;
      }
    });
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

  Future<void> handleNativeCallNotificationAction(
    Map<String, String> payload,
  ) async {
    final action = (payload['xmo_action'] ?? payload['action'] ?? 'open')
        .toLowerCase()
        .trim();
    if (action.isEmpty) return;

    if (_handlingNativeAction) {
      debugPrint('[VoipService] Native call action already in progress');
      return;
    }
    _handlingNativeAction = true;
    final roomId = _nativeCallRoomId(payload);
    final callId = _nativeCallId(payload);
    final deadline = DateTime.now().add(const Duration(seconds: 75));
    try {
      while (DateTime.now().isBefore(deadline)) {
        final session = _matchingNativeIncomingSession(
          roomId: roomId,
          callId: callId,
        );
        if (session != null) {
          if (action == 'answer') {
            await answerIncomingCall(session);
          } else if (action == 'decline') {
            await rejectIncomingCall(session);
          } else {
            await _pushCallScreen(session);
          }
          return;
        }

        final groupCall = _matchingNativeIncomingGroupCall(
          roomId: roomId,
          callId: callId,
        );
        if (groupCall != null) {
          if (action == 'answer') {
            await answerIncomingGroupCall(groupCall);
          } else if (action == 'decline') {
            rejectGroupCall(groupCall);
          } else {
            await _pushIncomingGroupCallScreen(groupCall);
          }
          return;
        }

        await _refreshCallsForNativeAction(roomId);
        await Future.delayed(const Duration(milliseconds: 250));
      }

      debugPrint(
        '[VoipService] Native call action had no matching incoming call: '
        '$payload',
      );
    } finally {
      _handlingNativeAction = false;
    }
  }

  String? _nativeCallRoomId(Map<String, String> payload) {
    for (final key in const [
      'room_id',
      'roomId',
      'room',
      'room_id!',
      'roomId!',
    ]) {
      final value = payload[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _nativeCallId(Map<String, String> payload) {
    for (final key in const [
      'call_id',
      'callId',
      'm.call.id',
      'm.call_id',
      'group_call_id',
      'groupCallId',
    ]) {
      final value = payload[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  CallSession? _matchingNativeIncomingSession({
    required String? roomId,
    required String? callId,
  }) {
    final candidates = <CallSession?>[
      incomingCall.value,
      _activeSession,
    ];
    for (final session in candidates) {
      if (session == null || session.isGroupCall) continue;
      if (session.direction != CallDirection.kIncoming) continue;
      if (session.state != CallState.kRinging) continue;
      final roomMatches =
          roomId == null || roomId.isEmpty || session.room.id == roomId;
      final callMatches =
          callId == null || callId.isEmpty || session.callId == callId;
      if (roomMatches && callMatches) {
        return session;
      }
    }
    return null;
  }

  GroupCall? _matchingNativeIncomingGroupCall({
    required String? roomId,
    required String? callId,
  }) {
    final candidates = <GroupCall?>[
      if (callId != null && callId.isNotEmpty) _voip?.getGroupCallById(callId),
      incomingGroupCall.value,
      if (roomId != null && roomId.isNotEmpty)
        _voip?.getGroupCallForRoom(roomId),
    ];

    for (final groupCall in candidates) {
      if (groupCall == null || groupCall.terminated) continue;
      if (groupCall.state == GroupCallState.Ended) continue;
      final roomMatches =
          roomId == null || roomId.isEmpty || groupCall.room.id == roomId;
      final callMatches =
          callId == null || callId.isEmpty || groupCall.groupCallId == callId;
      if (roomMatches && callMatches) {
        return groupCall;
      }
    }
    return null;
  }

  Future<void> _refreshCallsForNativeAction(String? roomId) async {
    final now = DateTime.now();
    final lastAttempt = _lastNativeActionSyncAttempt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 2)) {
      return;
    }
    _lastNativeActionSyncAttempt = now;
    try {
      final service = MatrixService();
      if (!service.isLoggedIn) return;
      await service.client.oneShotSync();
      if (roomId != null && roomId.isNotEmpty) {
        _voip?.getGroupCallForRoom(roomId);
      }
    } catch (e) {
      debugPrint('[VoipService] Native call sync refresh failed: $e');
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _setRecoveryStatus(CallRecoveryStatus status) {
    if (recoveryStatus.value == status) return;
    recoveryStatus.value = status;
    if (status == CallRecoveryStatus.reconnecting) {
      _recoveryTimeout?.cancel();
      _recoveryTimeout = Timer(const Duration(seconds: 30), () {
        if (recoveryStatus.value == CallRecoveryStatus.reconnecting) {
          recoveryStatus.value = CallRecoveryStatus.failed;
        }
      });
      return;
    }
    _recoveryTimeout?.cancel();
    _recoveryTimeout = null;
  }

  Future<void> _recoverActiveCall({required String reason}) async {
    if (!isInCall) {
      _setRecoveryStatus(CallRecoveryStatus.connected);
      return;
    }

    _setRecoveryStatus(CallRecoveryStatus.reconnecting);
    try {
      final service = MatrixService();
      if (service.isLoggedIn) {
        await service.client.oneShotSync();
      }

      final groupCall = _activeGroupCall;
      if (groupCall != null && !groupCall.terminated) {
        if (_needsGroupCallEnter(groupCall)) {
          await _enterGroupCall(groupCall);
        }
        _setRecoveryStatus(CallRecoveryStatus.reconnected);
        return;
      }

      final session = _activeSession;
      if (session != null && session.state != CallState.kEnded) {
        if (session.type == CallType.kVoice) {
          await _routeDirectVoiceCallToEarpiece();
        }
        _setRecoveryStatus(CallRecoveryStatus.reconnected);
        return;
      }

      _setRecoveryStatus(CallRecoveryStatus.failed);
    } catch (e) {
      debugPrint('[VoipService] Call recovery failed after $reason: $e');
      _setRecoveryStatus(CallRecoveryStatus.failed);
    }
  }

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
    if (_locallyClosedGroupCallIds.contains(groupCall.groupCallId)) {
      return;
    }
    if (!_supportsRoomCall(groupCall.room)) {
      await groupCall.terminate();
      return;
    }
    if (groupCall.state != GroupCallState.Entered) {
      unawaited(_startRingtone());
      if (_shouldOpenIncomingGroupCallFullscreen(groupCall.room)) {
        incomingGroupCall.value = null;
        _notifyCallStateChanged();
        await _pushIncomingGroupCallScreen(groupCall);
        return;
      }
      incomingGroupCall.value = groupCall;
      _notifyCallStateChanged();
      return;
    }
    _trackGroupCall(groupCall);
    unawaited(_stopRingtone());
    incomingGroupCall.value = null;
    await _pushGroupCallScreen(groupCall);
  }

  Future<void> answerIncomingCall(CallSession session) async {
    unawaited(_stopRingtone());
    _setRecoveryStatus(CallRecoveryStatus.reconnecting);
    if (_activeSession != session) {
      _trackSession(session, showIncomingBanner: false, playRingtone: false);
    }
    incomingCall.value = null;
    await session.answer();
    if (session.type == CallType.kVoice) {
      unawaited(_routeDirectVoiceCallToEarpiece());
    }
    unawaited(
      CallHistoryService().recordDirectCall(
        session,
        direction: CallHistoryDirection.incoming,
        status: CallHistoryStatus.answered,
      ),
    );
    await _pushCallScreen(session);
    _setRecoveryStatus(CallRecoveryStatus.connected);
  }

  Future<void> _routeDirectVoiceCallToEarpiece() async {
    try {
      await AndroidAudioManager()
          .setMode(AndroidAudioHardwareMode.inCommunication);
    } catch (e) {
      debugPrint('[VoipService] Failed to set direct voice audio mode: $e');
    }
    try {
      await webrtc.Helper.setSpeakerphoneOn(false);
    } catch (e) {
      debugPrint('[VoipService] Failed to route direct voice to earpiece: $e');
    }
  }

  Future<void> rejectIncomingCall(CallSession session) async {
    unawaited(_stopRingtone());
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

  Future<void> answerIncomingGroupCall(
    GroupCall groupCall, {
    bool openCallScreen = true,
  }) async {
    unawaited(_stopRingtone());
    _setRecoveryStatus(CallRecoveryStatus.reconnecting);
    if (_isActiveGroupCall(groupCall)) {
      incomingGroupCall.value = null;
      _locallyClosedGroupCallIds.remove(groupCall.groupCallId);
      if (_needsGroupCallEnter(groupCall)) {
        await _enterGroupCall(groupCall);
      }
      if (openCallScreen) {
        await _pushGroupCallScreen(groupCall);
      }
      _setRecoveryStatus(CallRecoveryStatus.connected);
      return;
    }
    if (isInCall) {
      throw StateError('You are already in a call');
    }
    incomingGroupCall.value = null;
    _rejectedGroupCallIds.remove(groupCall.groupCallId);
    _locallyClosedGroupCallIds.remove(groupCall.groupCallId);
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
    if (openCallScreen) {
      await _pushGroupCallScreen(groupCall);
    }
    _setRecoveryStatus(CallRecoveryStatus.connected);
  }

  bool _needsGroupCallEnter(GroupCall groupCall) {
    return groupCall.state != GroupCallState.Entered ||
        groupCall.localUserMediaStream?.stream == null;
  }

  Future<void> _enterGroupCall(GroupCall groupCall) async {
    try {
      await groupCall.enter();
      _setRecoveryStatus(CallRecoveryStatus.connected);
    } catch (e) {
      if (!_isNullMediaStreamCast(e)) rethrow;

      debugPrint(
        '[VOIP] Group call media init failed; retrying with audio only: $e',
      );
      final fallbackStream = await _createAudioOnlyGroupStream(groupCall);
      await groupCall.enter(stream: fallbackStream);
      _setRecoveryStatus(CallRecoveryStatus.connected);
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
    unawaited(_stopRingtone());
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

  Future<void> _pushIncomingGroupCallScreen(GroupCall groupCall) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      incomingGroupCall.value = groupCall;
      _notifyCallStateChanged();
      return;
    }
    if (_openingCallScreen) {
      incomingGroupCall.value = groupCall;
      _notifyCallStateChanged();
      return;
    }

    _openingCallScreen = true;
    try {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => IncomingGroupCallScreen(groupCall: groupCall),
          fullscreenDialog: true,
        ),
      );
    } finally {
      _openingCallScreen = false;
    }
  }
}

Uint8List _buildRingtoneWav() {
  const sampleRate = 22050;
  const channels = 1;
  const bitsPerSample = 16;
  const bytesPerSample = bitsPerSample ~/ 8;
  const durationMs = 1400;
  const sampleCount = sampleRate * durationMs ~/ 1000;
  const dataLength = sampleCount * channels * bytesPerSample;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  data.setUint16(32, channels * bytesPerSample, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final ms = i * 1000 / sampleRate;
    final active = ms < 520 || (ms >= 720 && ms < 1120);
    final time = i / sampleRate;
    final envelope = active ? _ringtoneEnvelope(ms) : 0.0;
    final wave = math.sin(2 * math.pi * 520 * time) * 0.72 +
        math.sin(2 * math.pi * 780 * time) * 0.28;
    final sample = (wave * envelope * 32767).clamp(-32768, 32767).round();
    data.setInt16(44 + i * 2, sample, Endian.little);
  }

  return bytes;
}

double _ringtoneEnvelope(double ms) {
  final localMs = ms >= 720 ? ms - 720 : ms;
  final attack = (localMs / 55).clamp(0.0, 1.0);
  final release = ((520 - localMs) / 90).clamp(0.0, 1.0);
  return math.min(attack, release) * 0.85;
}

class _RingtoneAudioSource extends StreamAudioSource {
  final Uint8List bytes;

  _RingtoneAudioSource(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
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
  Future<void> playRingtone() async {
    unawaited(VoipService()._startRingtone());
  }

  @override
  Future<void> stopRingtone() => VoipService()._stopRingtone();

  @override
  Future<void> handleNewCall(CallSession session) => onNewCall(session);

  @override
  Future<void> handleCallEnded(CallSession session) async {
    await VoipService()._stopRingtone();
  }

  @override
  Future<void> handleMissedCall(CallSession session) {
    unawaited(VoipService()._stopRingtone());
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
    await VoipService()._stopRingtone();
    VoipService()._ownedGroupCallIds.remove(groupCall.groupCallId);
    VoipService()._rejectedGroupCallIds.remove(groupCall.groupCallId);
    VoipService()._locallyClosedGroupCallIds.add(groupCall.groupCallId);
    if (VoipService()._isActiveGroupCall(groupCall)) {
      VoipService()._cleanupGroupCall();
    } else {
      VoipService()._notifyCallStateChanged();
    }
  }
}
