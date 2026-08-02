import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:matrix/matrix.dart';

import '../models/direct_chat_models.dart';
import '../utils/message_presentation.dart';

class SharedMediaLinkItem {
  final String id;
  final String url;
  final String eventId;
  final DateTime timestamp;
  final String senderId;

  const SharedMediaLinkItem({
    required this.id,
    required this.url,
    required this.eventId,
    required this.timestamp,
    required this.senderId,
  });

  factory SharedMediaLinkItem.fromJson(Map<String, dynamic> json) {
    return SharedMediaLinkItem(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      eventId: json['eventId'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? 0,
      ),
      senderId: json['senderId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'eventId': eventId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'senderId': senderId,
      };
}

class SharedMediaIndexSnapshot {
  final List<SharedMediaItem> photos;
  final List<SharedMediaItem> videos;
  final List<SharedMediaItem> audio;
  final List<SharedMediaItem> files;
  final List<SharedMediaLinkItem> links;
  final bool historyComplete;

  const SharedMediaIndexSnapshot({
    this.photos = const [],
    this.videos = const [],
    this.audio = const [],
    this.files = const [],
    this.links = const [],
    this.historyComplete = false,
  });
}

/// A bounded history-indexing result. The caller can render cached results
/// immediately and continue indexing later without restarting at page one.
class SharedMediaIndexProgress {
  final SharedMediaIndexSnapshot snapshot;
  final int pagesIndexed;
  final bool cancelled;

  const SharedMediaIndexProgress({
    required this.snapshot,
    required this.pagesIndexed,
    this.cancelled = false,
  });
}

class SharedMediaIndexService {
  SharedMediaIndexService._();

  static final SharedMediaIndexService instance = SharedMediaIndexService._();
  static const String boxName = 'xmo_shared_media_index';
  final Set<String> _cancelledHistoryRuns = <String>{};

  static final RegExp _linkPattern = RegExp(
    r'(?:(?:https?|ftp)://[^\s<>()]+|(?:mailto:|tel:|sms:|geo:|magnet:|matrix:)[^\s<>()]+|www\.[^\s<>()]+|(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+(?:com|org|net|edu|gov|io|co|in|me|app|dev|ai|info|biz|xyz|site|online|store|tech|link|ly|to|tv|uk|us|ca|au|de|fr|jp|cn|ru|br|za|nl|it|es|se|no|fi|ch|be|at|dk|pl|ie|sg|ae|sa|qa|kw|om|bh|pk|bd|lk|np|id|my|th|vn|ph)(?:/[^\s<>()]*)?)',
    caseSensitive: false,
  );

  Future<Box> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  Future<SharedMediaIndexSnapshot> read({
    required String ownerUserId,
    required String roomId,
  }) async {
    final box = await _box();
    return _snapshotFromState(
        _stateFromRaw(box.get(_key(ownerUserId, roomId))));
  }

  Future<SharedMediaIndexSnapshot> indexTimeline({
    required String ownerUserId,
    required Room room,
    required Timeline timeline,
    bool historyComplete = false,
    List<Event>? eventsToIndex,
    bool countHistoryPage = false,
  }) async {
    final box = await _box();
    final key = _key(ownerUserId, room.id);
    final state = _stateFromRaw(box.get(key));
    _indexEvents(
      state,
      eventsToIndex ?? timeline.events,
      countHistoryPage: countHistoryPage,
      loadedEventCount: timeline.events.length,
    );
    if (historyComplete) {
      state['historyComplete'] = true;
    }
    state['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await box.put(key, state);
    return _snapshotFromState(state);
  }

  /// Indexes a small, persisted slice of room history.
  ///
  /// The Matrix timeline owns the pagination token. This service persists the
  /// room checkpoint and the event IDs it has already consumed, so reopening
  /// Shared Media continues from that point instead of rescanning every loaded
  /// event and then fetching the complete history again.
  Future<SharedMediaIndexProgress> indexNextHistoryBatch({
    required String ownerUserId,
    required Room room,
    required Timeline timeline,
    int pageSize = 100,
    int maxPages = 1,
    String? runId,
    void Function(SharedMediaIndexSnapshot snapshot)? onSnapshot,
  }) async {
    final normalizedMaxPages = maxPages.clamp(1, 10);
    final normalizedRunId = runId ?? _key(ownerUserId, room.id);
    var pagesIndexed = 0;
    var snapshot = await indexTimeline(
      ownerUserId: ownerUserId,
      room: room,
      timeline: timeline,
      historyComplete: !timeline.canRequestHistory,
    );
    onSnapshot?.call(snapshot);

    while (!snapshot.historyComplete && pagesIndexed < normalizedMaxPages) {
      if (_cancelledHistoryRuns.contains(normalizedRunId)) {
        return SharedMediaIndexProgress(
          snapshot: snapshot,
          pagesIndexed: pagesIndexed,
          cancelled: true,
        );
      }

      final beforeEventCount = timeline.events.length;
      var fetchedEvents = const <Event>[];
      var loaded = false;
      Object? lastError;
      for (var attempt = 0; attempt < 3 && !loaded; attempt++) {
        try {
          await timeline.requestHistory(historyCount: pageSize);
          loaded = timeline.events.length > beforeEventCount;
          if (loaded) {
            fetchedEvents =
                timeline.events.skip(beforeEventCount).toList(growable: false);
          }
        } catch (error) {
          lastError = error;
          if (attempt < 2) {
            await Future<void>.delayed(
              Duration(milliseconds: 400 * (1 << attempt)),
            );
          }
        }
      }
      if (!loaded && lastError != null) {
        debugPrint('[SharedMediaIndex] History batch failed: $lastError');
        break;
      }

      pagesIndexed++;
      snapshot = await indexTimeline(
        ownerUserId: ownerUserId,
        room: room,
        timeline: timeline,
        historyComplete: !loaded || !timeline.canRequestHistory,
        eventsToIndex: fetchedEvents,
        countHistoryPage: true,
      );
      onSnapshot?.call(snapshot);
      if (!loaded) break;
      await Future<void>.delayed(Duration.zero);
    }

    return SharedMediaIndexProgress(
      snapshot: snapshot,
      pagesIndexed: pagesIndexed,
    );
  }

  void cancelHistoryIndex({
    required String ownerUserId,
    required String roomId,
    String? runId,
  }) {
    _cancelledHistoryRuns.add(runId ?? _key(ownerUserId, roomId));
  }

  Future<SharedMediaIndexSnapshot> scanFullHistory({
    required String ownerUserId,
    required Room room,
    int pageSize = 100,
    void Function(SharedMediaIndexSnapshot snapshot)? onSnapshot,
  }) async {
    final timeline = await room.getTimeline();
    SharedMediaIndexProgress progress;
    do {
      progress = await indexNextHistoryBatch(
        ownerUserId: ownerUserId,
        room: room,
        timeline: timeline,
        pageSize: pageSize,
        maxPages: 3,
        onSnapshot: onSnapshot,
      );
    } while (!progress.snapshot.historyComplete && !progress.cancelled);
    return progress.snapshot;
  }

  Map<String, dynamic> _stateFromRaw(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{
      'media': <String, dynamic>{},
      'links': <String, dynamic>{},
      'indexedEventIds': <String, dynamic>{},
      'pagination': <String, dynamic>{},
      'historyComplete': false,
    };
  }

  void _indexEvents(
    Map<String, dynamic> state,
    List<Event> events, {
    bool countHistoryPage = false,
    int? loadedEventCount,
  }) {
    final media = _nestedMap(state, 'media');
    final links = _nestedMap(state, 'links');
    final indexedEventIds = _nestedMap(state, 'indexedEventIds');
    final pagination = _nestedMap(state, 'pagination');

    for (final event in events) {
      if (event.type != EventTypes.Message) continue;
      final alreadyIndexed = indexedEventIds.containsKey(event.eventId);
      if (event.redacted) {
        media.remove(event.eventId);
        links.removeWhere((_, value) {
          if (value is! Map) return false;
          return value['eventId'] == event.eventId;
        });
        indexedEventIds[event.eventId] =
            event.originServerTs.millisecondsSinceEpoch;
        continue;
      }
      if (alreadyIndexed) continue;

      final msgType = event.messageType;
      if (_isMediaMessage(msgType)) {
        media[event.eventId] = _mediaJsonFromEvent(event);
      }

      final visibleBody = matrixVisibleBody(event);
      if (visibleBody.isNotEmpty) {
        for (final url in _extractLinks(visibleBody)) {
          final id = '${event.eventId}:$url';
          links[id] = SharedMediaLinkItem(
            id: id,
            url: url,
            eventId: event.eventId,
            timestamp: event.originServerTs,
            senderId: event.senderId,
          ).toJson();
        }
      }
      indexedEventIds[event.eventId] =
          event.originServerTs.millisecondsSinceEpoch;
    }

    if (events.isNotEmpty) {
      final newest = events.first;
      final oldest = events.last;
      pagination['latestEventId'] = newest.eventId;
      pagination['latestTimestamp'] =
          newest.originServerTs.millisecondsSinceEpoch;
      pagination['oldestEventId'] = oldest.eventId;
      pagination['oldestTimestamp'] =
          oldest.originServerTs.millisecondsSinceEpoch;
      pagination['lastIndexedBatchSize'] = events.length;
      pagination['loadedEventCount'] = loadedEventCount ?? events.length;
      pagination['checkpointVersion'] = 2;
      if (countHistoryPage) {
        pagination['pagesIndexed'] =
            ((pagination['pagesIndexed'] as num?)?.toInt() ?? 0) + 1;
      }
    }
  }

  Map<String, dynamic> _nestedMap(Map<String, dynamic> state, String key) {
    final current = state[key];
    if (current is Map) {
      final mapped = current.map((k, v) => MapEntry(k.toString(), v));
      state[key] = mapped;
      return mapped;
    }
    final next = <String, dynamic>{};
    state[key] = next;
    return next;
  }

  SharedMediaIndexSnapshot _snapshotFromState(Map<String, dynamic> state) {
    final media = _nestedMap(state, 'media');
    final links = _nestedMap(state, 'links');

    final mediaItems = media.values
        .whereType<Map>()
        .map((value) {
          try {
            return _mediaFromJson(
              value.map((key, value) => MapEntry(key.toString(), value)),
            );
          } catch (e) {
            debugPrint('[SharedMediaIndex] Invalid media entry skipped: $e');
            return null;
          }
        })
        .whereType<SharedMediaItem>()
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final linkItems = links.values
        .whereType<Map>()
        .map((value) {
          try {
            return SharedMediaLinkItem.fromJson(
              value.map((key, value) => MapEntry(key.toString(), value)),
            );
          } catch (e) {
            debugPrint('[SharedMediaIndex] Invalid link entry skipped: $e');
            return null;
          }
        })
        .whereType<SharedMediaLinkItem>()
        .where((item) => item.url.isNotEmpty && item.eventId.isNotEmpty)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return SharedMediaIndexSnapshot(
      photos: mediaItems.where((m) => m.type == MediaType.image).toList(),
      videos: mediaItems.where((m) => m.type == MediaType.video).toList(),
      audio: mediaItems.where((m) => m.type == MediaType.audio).toList(),
      files: mediaItems.where((m) => m.type == MediaType.file).toList(),
      links: linkItems,
      historyComplete: state['historyComplete'] == true,
    );
  }

  Map<String, dynamic> _mediaJsonFromEvent(Event event) {
    final content = event.content;
    final info = content['info'];
    final infoMap = info is Map ? info : const <String, dynamic>{};
    return {
      'eventId': event.eventId,
      'type': _mediaTypeForMessageType(event.messageType).name,
      'thumbnailUrl': infoMap['thumbnail_url'],
      'url': content['url'],
      'filename': matrixAttachmentFileName(event),
      'fileSize': infoMap['size'],
      'timestamp': event.originServerTs.millisecondsSinceEpoch,
      'senderId': event.senderId,
    };
  }

  SharedMediaItem _mediaFromJson(Map<String, dynamic> json) {
    return SharedMediaItem(
      eventId: json['eventId'] as String? ?? '',
      type: MediaType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => MediaType.file,
      ),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      url: json['url'] as String?,
      filename: json['filename'] as String? ?? 'File',
      fileSize: json['fileSize'] is int ? json['fileSize'] as int : null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? 0,
      ),
      senderId: json['senderId'] as String? ?? '',
    );
  }

  bool _isMediaMessage(String? msgType) {
    return msgType == MessageTypes.Image ||
        msgType == MessageTypes.Video ||
        msgType == MessageTypes.Audio ||
        msgType == MessageTypes.File;
  }

  MediaType _mediaTypeForMessageType(String? msgType) {
    if (msgType == MessageTypes.Image) return MediaType.image;
    if (msgType == MessageTypes.Video) return MediaType.video;
    if (msgType == MessageTypes.Audio) return MediaType.audio;
    return MediaType.file;
  }

  Iterable<String> _extractLinks(String text) sync* {
    for (final match in _linkPattern.allMatches(text)) {
      final raw = match.group(0);
      if (raw == null) continue;
      final trimmed = _trimLink(raw);
      if (trimmed.isNotEmpty) yield trimmed;
    }
  }

  String _trimLink(String value) {
    const trailing = '.,;:!?)]}\'"';
    var text = value;
    while (text.isNotEmpty && trailing.contains(text[text.length - 1])) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  String _key(String ownerUserId, String roomId) => '$ownerUserId::$roomId';
}
