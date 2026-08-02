import 'package:matrix/matrix.dart';

enum XmoGroupCallType { voice, video }

/// Product-level group call state kept stable across Matrix SDK migrations.
class XmoGroupCall {
  XmoGroupCall({required this.session, required this.type});

  final GroupCallSession session;
  final XmoGroupCallType type;

  String get groupCallId => session.groupCallId;
  Room get room => session.room;
  GroupCallState get state => session.state;
  bool get terminated => state == GroupCallState.ended;

  List<User> get participants => session.participants
      .map(
        (participant) =>
            room.unsafeGetUserFromMemoryOrFallback(participant.userId),
      )
      .toList(growable: false);

  String? get activeSpeaker => session.backend.activeSpeaker?.userId;
  List<WrappedMediaStream> get userMediaStreams =>
      session.backend.userMediaStreams;
  WrappedMediaStream? get localUserMediaStream =>
      session.backend.localUserMediaStream;
  bool get isMicrophoneMuted => session.backend.isMicrophoneMuted;
  bool get isLocalVideoMuted => session.backend.isLocalVideoMuted;

  Stream<GroupCallState> get stateStream => session.matrixRTCEventStream.stream
      .where((event) => event is GroupCallStateChanged)
      .cast<GroupCallStateChanged>()
      .map((event) => event.state);
  Stream<MatrixRTCCallEvent> get eventStream =>
      session.matrixRTCEventStream.stream;
  Stream<WrappedMediaStream> get streamAddStream {
    final backend = session.backend;
    return backend is MeshBackend
        ? backend.onStreamAdd.stream
        : const Stream<WrappedMediaStream>.empty();
  }

  Stream<WrappedMediaStream> get streamRemovedStream {
    final backend = session.backend;
    return backend is MeshBackend
        ? backend.onStreamRemoved.stream
        : const Stream<WrappedMediaStream>.empty();
  }

  Future<void> enter({WrappedMediaStream? stream}) =>
      session.enter(stream: stream);
  Future<void> leave() => session.leave();

  // MatrixRTC uses membership-based calls. Ending locally removes this device's
  // membership; XMO's push marker remains the product-level call notification.
  Future<void> terminate() => session.leave();

  Future<void> setMicrophoneMuted(bool muted) =>
      session.backend.setDeviceMuted(session, muted, MediaInputKind.audioinput);

  Future<void> setLocalVideoMuted(bool muted) =>
      session.backend.setDeviceMuted(session, muted, MediaInputKind.videoinput);
}

extension XmoWrappedMediaStream on WrappedMediaStream {
  String get userId => participant.userId;
}
