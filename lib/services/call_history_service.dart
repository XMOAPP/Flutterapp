import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:matrix/matrix.dart';

import 'matrix_service.dart';

enum CallHistoryKind { direct, group }

enum CallHistoryDirection { incoming, outgoing }

enum CallHistoryStatus { answered, missed, rejected, ended }

class CallHistoryEntry {
  final String id;
  final String roomId;
  final String roomName;
  final String? avatarUrl;
  final CallHistoryKind kind;
  final CallHistoryDirection direction;
  final CallHistoryStatus status;
  final bool video;
  final DateTime timestamp;
  final Duration? duration;

  const CallHistoryEntry({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.kind,
    required this.direction,
    required this.status,
    required this.video,
    required this.timestamp,
    this.avatarUrl,
    this.duration,
  });

  String get title => roomName.trim().isEmpty ? 'Unknown' : roomName;

  String get subtitle {
    final callType = video ? 'video' : 'voice';
    final scope = kind == CallHistoryKind.group ? 'group ' : '';
    final label = switch (status) {
      CallHistoryStatus.answered => direction == CallHistoryDirection.incoming
          ? 'Incoming $scope$callType call'
          : 'Outgoing $scope$callType call',
      CallHistoryStatus.ended => direction == CallHistoryDirection.incoming
          ? 'Incoming $scope$callType call'
          : 'Outgoing $scope$callType call',
      CallHistoryStatus.missed => 'Missed $scope$callType call',
      CallHistoryStatus.rejected => direction == CallHistoryDirection.incoming
          ? 'Rejected $scope$callType call'
          : 'Declined $scope$callType call',
    };
    final callDuration = duration;
    if (callDuration == null || callDuration.inSeconds <= 0) return label;
    return '$label • ${_formatDuration(callDuration)}';
  }

  bool get isMissed => status == CallHistoryStatus.missed;

  bool get isRejected => status == CallHistoryStatus.rejected;

  bool get isOutgoing => direction == CallHistoryDirection.outgoing;

  bool get isIncoming => direction == CallHistoryDirection.incoming;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roomId': roomId,
      'roomName': roomName,
      'avatarUrl': avatarUrl,
      'kind': kind.name,
      'direction': direction.name,
      'status': status.name,
      'video': video,
      'timestamp': timestamp.toIso8601String(),
      'durationMs': duration?.inMilliseconds,
    };
  }

  factory CallHistoryEntry.fromJson(Map<dynamic, dynamic> json) {
    final durationMs = json['durationMs'];
    return CallHistoryEntry(
      id: json['id'] as String? ?? '',
      roomId: json['roomId'] as String? ?? '',
      roomName: json['roomName'] as String? ?? 'Unknown',
      avatarUrl: json['avatarUrl'] as String?,
      kind: CallHistoryKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => CallHistoryKind.direct,
      ),
      direction: CallHistoryDirection.values.firstWhere(
        (value) => value.name == json['direction'],
        orElse: () => CallHistoryDirection.incoming,
      ),
      status: CallHistoryStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => CallHistoryStatus.ended,
      ),
      video: json['video'] as bool? ?? false,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      duration: durationMs is int ? Duration(milliseconds: durationMs) : null,
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class CallHistoryService {
  static final CallHistoryService _instance = CallHistoryService._internal();
  factory CallHistoryService() => _instance;
  CallHistoryService._internal();

  static const String _boxName = 'xmo_call_history';
  static const int _maxEntries = 250;

  final ValueNotifier<List<CallHistoryEntry>> entries =
      ValueNotifier<List<CallHistoryEntry>>(const []);

  Box? _box;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _box = Hive.isBoxOpen(_boxName)
        ? Hive.box(_boxName)
        : await Hive.openBox(_boxName);
    _loaded = true;
    _refreshFromBox();
  }

  int get count => entries.value.length;

  Future<void> recordDirectCall(
    CallSession session, {
    required CallHistoryDirection direction,
    required CallHistoryStatus status,
    Duration? duration,
  }) {
    return recordRoomCall(
      room: session.room,
      kind: CallHistoryKind.direct,
      direction: direction,
      status: status,
      video: session.type == CallType.kVideo,
      duration: duration,
    );
  }

  Future<void> recordGroupCall(
    GroupCall groupCall, {
    required CallHistoryDirection direction,
    required CallHistoryStatus status,
    Duration? duration,
  }) {
    return recordRoomCall(
      room: groupCall.room,
      kind: CallHistoryKind.group,
      direction: direction,
      status: status,
      video: groupCall.type == GroupCallType.Video,
      duration: duration,
    );
  }

  Future<void> recordRoomCall({
    required Room room,
    required CallHistoryKind kind,
    required CallHistoryDirection direction,
    required CallHistoryStatus status,
    required bool video,
    Duration? duration,
  }) async {
    await ensureLoaded();
    final entry = CallHistoryEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}_${room.id}',
      roomId: room.id,
      roomName: MatrixService.cleanName(MatrixService().getResolvedDisplayName(room)),
      avatarUrl: room.avatar?.toString(),
      kind: kind,
      direction: direction,
      status: status,
      video: video,
      timestamp: DateTime.now(),
      duration: duration,
    );

    await _box!.put(entry.id, entry.toJson());
    await _trim();
    _refreshFromBox();
  }

  Future<void> clear() async {
    await ensureLoaded();
    await _box!.clear();
    _refreshFromBox();
  }

  void _refreshFromBox() {
    final box = _box;
    if (box == null) return;
    final next = box.values
        .whereType<Map>()
        .map(CallHistoryEntry.fromJson)
        .where((entry) => entry.id.isNotEmpty)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    entries.value = List.unmodifiable(next);
  }

  Future<void> _trim() async {
    final box = _box;
    if (box == null || box.length <= _maxEntries) return;
    final sorted = box.values
        .whereType<Map>()
        .map(CallHistoryEntry.fromJson)
        .where((entry) => entry.id.isNotEmpty)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (final entry in sorted.skip(_maxEntries)) {
      await box.delete(entry.id);
    }
  }
}
