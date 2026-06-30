import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:record/record.dart';
import '../theme.dart';
import '../providers/matrix_provider.dart';
import '../services/matrix_service.dart';
import '../services/group_service.dart';
import '../services/app_settings_service.dart';
import '../services/voip_service.dart';
import '../services/room_controls_service.dart';
import '../services/shared_media_index_service.dart';
import '../services/transfer_queue_service.dart';
import '../widgets/matrix_chat/album_media_viewer.dart';
import '../widgets/matrix_chat/fullscreen_image_viewer.dart';
import '../widgets/matrix_chat/fullscreen_video_player.dart';
import '../widgets/matrix_chat/reply_preview.dart';
import '../widgets/matrix_chat/pinned_messages_banner.dart';
import '../widgets/matrix_chat/mention_autocomplete.dart';
import '../widgets/incoming_call_fullscreen_scope.dart';
import '../widgets/chat/old_messages_loading_indicator.dart';
import '../widgets/direct_chat/typing_indicator.dart';
import '../widgets/direct_chat/message_reactions.dart';
import '../widgets/direct_chat/read_receipt.dart';
import '../widgets/story/story_avatar.dart';
import '../models/group_models.dart';
import '../services/direct_chat_service.dart';
import '../services/audio_file_reader_stub.dart'
    if (dart.library.io) '../services/audio_file_reader_io.dart';
import 'camera_capture_screen.dart';
import 'media_preview_screen.dart';
import 'matrix_chat/attachment_sheet.dart';
import 'matrix_chat/chat_app_bar.dart';
import 'matrix_chat/chat_input_bar.dart';
import 'matrix_chat/chat_space_background.dart';
import 'matrix_chat/controllers/chat_call_coordinator.dart';
import 'matrix_chat/controllers/chat_composer_controller.dart';
import 'matrix_chat/controllers/chat_reply_reaction_controller.dart';
import 'matrix_chat/controllers/chat_timeline_controller.dart';
import 'matrix_chat/controllers/chat_transfer_controller.dart';
import 'matrix_chat/forward_message_sheet.dart';
import 'matrix_chat/media_handler.dart';
import 'matrix_chat/message_widgets.dart';
import 'native_share_stub.dart' if (dart.library.io) 'native_share.dart'
    as native_share;

// Web download helper
import 'web_download_stub.dart' if (dart.library.js_interop) 'web_download.dart'
    as web_download;

// Web video view

const String _pollStartEventType = 'm.poll.start';
const String _pollResponseEventType = 'm.poll.response';
const String _pollStartContentKey = 'm.poll.start';
const String _pollResponseContentKey = 'm.poll.response';
const String _unstablePollStartContentKey = 'org.matrix.msc3381.poll.start';
const String _unstablePollResponseContentKey =
    'org.matrix.msc3381.poll.response';
const double _jumpToLatestShowExtent = 160;

double _responsiveBubbleWidth(
  BuildContext context, {
  required double compact,
  required double regular,
}) {
  final viewport = MediaQuery.sizeOf(context).width;
  final target = viewport < 390 ? compact : regular;
  return math.min(target, math.max(220, viewport - 56));
}

const double _jumpToLatestHideExtent = 56;

/// Real-time Matrix chat screen for a given Room
class MatrixChatScreen extends StatefulWidget {
  final Room? room;
  final PublicRoomsChunk? previewChannel;
  final MatrixProvider matrixProvider;
  final String? initialComposerText;
  final PrivateReplyDraft? initialPrivateReply;
  final String? initialHighlightedEventId;
  final bool? previewIsChannelHint;

  const MatrixChatScreen({
    super.key,
    this.room,
    this.previewChannel,
    required this.matrixProvider,
    this.initialComposerText,
    this.initialPrivateReply,
    this.initialHighlightedEventId,
    this.previewIsChannelHint,
  }) : assert(room != null || previewChannel != null);

  @override
  State<MatrixChatScreen> createState() => _MatrixChatScreenState();
}

class PrivateReplyDraft {
  final String sourceRoomId;
  final String sourceRoomName;
  final String sourceEventId;
  final String senderId;
  final String senderName;
  final String preview;
  final String msgtype;

  const PrivateReplyDraft({
    required this.sourceRoomId,
    required this.sourceRoomName,
    required this.sourceEventId,
    required this.senderId,
    required this.senderName,
    required this.preview,
    required this.msgtype,
  });

  Map<String, dynamic> toJson() => {
        'source_room_id': sourceRoomId,
        'source_room_name': sourceRoomName,
        'source_event_id': sourceEventId,
        'sender_id': senderId,
        'sender_name': senderName,
        'preview': preview,
        'msgtype': msgtype,
      };
}

class _MatrixChatScreenState extends State<MatrixChatScreen> {
  final _composerController = ChatComposerController();
  final _timelineController = ChatTimelineController();
  final _replyReactionController =
      ChatReplyReactionController<Event, PrivateReplyDraft>();
  final _transferController =
      ChatTransferController<_PendingUpload, _PendingAlbumUpload>();
  final _callCoordinator = ChatCallCoordinator();
  final _scrollCtrl = ScrollController();
  Timeline? _timeline;
  bool _uploading = false;
  bool _recording = false;
  bool _recordingPaused = false;
  Duration _recordingDuration = Duration.zero;
  List<double> _recordingWaveform = const [];
  bool? _previewIsChannel;
  StreamSubscription<EventUpdate>? _eventSub;
  StreamSubscription<dynamic>? _typingSub;
  late MediaHandler _mediaHandler;
  List<Event> _pinnedEvents = []; // Track pinned messages
  int? _pinnedBannerIndex;
  double _lastPinnedScrollOffset = 0;
  double _lastPinnedBannerScrollSyncOffset = 0;
  bool _isJumpingToPinnedMessage = false;
  List<GroupMember> _groupMembers = []; // Track group members for mentions
  MemberRestriction? _ownRestriction;
  final _mentionAutocomplete = ValueNotifier<_MentionAutocompleteState>(
      _MentionAutocompleteState.hidden);
  List<String> _typingUsers = []; // Track typing users
  late DirectChatService _directChatService;
  Timer? _typingTimer; // Timer for sending typing indicators
  Timer? _recordingTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  DateTime? _recordingStartedAt;
  DateTime? _lastRecordingWaveformUiUpdate;
  Duration _recordingAccumulatedDuration = Duration.zero;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, String> _optimisticPollVotes = {};
  final Map<String, bool> _savedMessageStatusCache = {};
  final Map<String, Future<bool>> _savedMessageStatusFutures = {};
  final Set<String> _preloadedVideoThumbnailEventIds = {};
  bool _timelineUiRefreshScheduled = false;
  bool _pendingTimelineAutoScroll = false;
  int _pendingNewMessagesBelow = 0;
  Timer? _readMarkerDebounce;
  Timer? _sharedMediaIndexDebounce;
  Timer? _stateRefreshDebounce;
  bool _uploadProgressFrameScheduled = false;
  bool _uploadPreviewFrameScheduled = false;
  String? _highlightedEventId;
  Timer? _highlightTimer;
  bool _handledInitialHighlightedEvent = false;
  final _transferQueue = TransferQueueService.instance;
  final _appSettingsService = AppSettingsService();
  AppSettings _appSettings = const AppSettings(
    notificationsEnabled: true,
    readReceiptsEnabled: true,
    typingIndicatorsEnabled: true,
    autoDownloadMedia: true,
    defaultChatFilter: 'all',
  );
  bool get _isUploadBusy =>
      _uploading ||
      _pendingUploads.any((upload) => !upload.failed && !upload.cancelled) ||
      _pendingAlbumUploads.isNotEmpty;

  TextEditingController get _textCtrl => _composerController.textController;
  FocusNode get _textFocusNode => _composerController.focusNode;
  bool get _loading => _timelineController.loading;
  set _loading(bool value) => _timelineController.loading = value;
  bool get _loadingHistory => _timelineController.loadingHistory;
  set _loadingHistory(bool value) => _timelineController.loadingHistory = value;
  bool get _historyExhausted => _timelineController.historyExhausted;
  set _historyExhausted(bool value) =>
      _timelineController.historyExhausted = value;
  bool get _showJumpToLatestButton =>
      _timelineController.showJumpToLatestButton;
  set _showJumpToLatestButton(bool value) =>
      _timelineController.showJumpToLatestButton = value;
  int get _newMessagesBelowCount => _timelineController.newMessagesBelowCount;
  set _newMessagesBelowCount(int value) =>
      _timelineController.newMessagesBelowCount = value;
  bool get _scrollToBottomScheduled =>
      _timelineController.scrollToBottomScheduled;
  set _scrollToBottomScheduled(bool value) =>
      _timelineController.scrollToBottomScheduled = value;
  Event? get _replyToEvent => _replyReactionController.replyTo;
  set _replyToEvent(Event? value) => _replyReactionController.replyTo = value;
  PrivateReplyDraft? get _privateReplyDraft =>
      _replyReactionController.privateReply;
  set _privateReplyDraft(PrivateReplyDraft? value) =>
      _replyReactionController.privateReply = value;
  List<_PendingUpload> get _pendingUploads => _transferController.uploads;
  List<_PendingAlbumUpload> get _pendingAlbumUploads =>
      _transferController.albums;
  Set<String> get _cancelledPendingUploadIds =>
      _transferController.cancelledUploadIds;
  Map<String, DateTime> get _pendingUploadProgressUiUpdates =>
      _transferController.progressUiUpdates;
  Set<String> get _dismissedGroupCallBannerIds =>
      _callCoordinator.dismissedGroupCallBannerIds;

  Room? get _room => widget.room;
  String get _myUserId => widget.matrixProvider.userId ?? '';
  MatrixService get _matrixService => widget.matrixProvider.service;
  bool get _isDirectRoom =>
      _room != null && _matrixService.isDirectRoom(_room!);

  /// Determines if the room is a group or channel for join button text
  String _getJoinButtonText() {
    if (_room == null) {
      return _previewIsChannel == true ? 'Join Channel' : 'Join Group';
    }
    if (_room!.isChannel) return 'Join Channel';
    if (_isDirectRoom) return 'Open Chat';

    final typeState = _room!.getState(MatrixService.roomTypeStateType);
    if (typeState?.content['is_group'] == true) return 'Join Group';
    return 'Join Group';
  }

  @override
  void initState() {
    super.initState();
    _previewIsChannel = widget.previewIsChannelHint;
    _privateReplyDraft = widget.initialPrivateReply;
    final initialComposerText = widget.initialComposerText;
    if (initialComposerText != null && initialComposerText.isNotEmpty) {
      _composerController.setInitialText(initialComposerText);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocusNode.requestFocus();
      });
    }
    _mediaHandler = MediaHandler(
      matrixProvider: widget.matrixProvider,
      context: context,
    );
    _directChatService = DirectChatService(widget.matrixProvider.service);
    _initializeChat();
    _scrollCtrl.addListener(_handleChatScroll);
    _textCtrl.addListener(() {
      final has = _textCtrl.text.trim().isNotEmpty;

      // Check for mention trigger (@)
      _checkForMention();

      // Send typing indicator in direct chats
      if (_isDirectRoom) {
        _handleTyping(has);
      }
    });

    // Load group members if this is a group
    if (_room != null && !_isDirectRoom) {
      _loadGroupMembers();
      _loadOwnRestriction();
    }

    // Listen for typing indicators in direct chats
    if (_isDirectRoom) {
      _listenForTyping();
    }
  }

  Future<void> _loadAppSettings() async {
    final settings = await _appSettingsService.load();
    if (!mounted) return;
    setState(() => _appSettings = settings);
  }

  Future<void> _initializeChat() async {
    await _loadAppSettings();
    if (!mounted) return;
    await _restorePendingTransfers();
    _loadPreviewType();
    _loadTimeline();
  }

  Future<void> _restorePendingTransfers() async {
    final room = _room;
    if (room == null) return;
    await _transferQueue.init();
    final jobs = _transferQueue.jobsForRoom(room.id).where((job) {
      return job.direction == TransferDirection.upload &&
          job.status != TransferStatus.completed;
    }).toList();
    if (jobs.isEmpty) return;

    final restored = <_PendingUpload>[];
    for (final job in jobs) {
      try {
        final bytes = await _transferQueue.readPayload(job);
        final thumbnailBytes = await _transferQueue.readThumbnail(job);
        restored.add(
          _PendingUpload(
            id: job.id,
            transferJobId: job.id,
            bytes: bytes,
            fileName: job.fileName,
            mimeType: job.mimeType,
            isVideo: job.kind == TransferKind.video,
            isAudio: job.kind == TransferKind.audio ||
                job.kind == TransferKind.voice,
            isFile: job.kind == TransferKind.file,
            totalBytes: job.totalBytes,
            createdAt: job.createdAt,
            thumbnailBytes: thumbnailBytes,
          )
            ..uploadedBytes = job.uploadedBytes
            ..failed = job.status == TransferStatus.failed
            ..cancelled = job.status == TransferStatus.cancelled
            ..error = job.error,
        );
      } catch (e) {
        debugPrint('[TransferQueue] Failed to restore ${job.id}: $e');
        await _transferQueue.markFailed(job.id, e);
      }
    }

    if (!mounted || restored.isEmpty) return;
    setState(() => _pendingUploads.addAll(restored));

    final queued = restored.where((upload) {
      if (upload.cancelled) return false;
      if (!upload.failed) return true;
      return _transferQueue.shouldAutoRetry(upload.id);
    }).toList(growable: false);
    if (queued.isNotEmpty) {
      for (final upload in queued) {
        if (upload.failed) {
          _schedulePendingUploadRetry(room.id, upload);
        }
      }
      final ready = queued.where((upload) => !upload.failed).toList();
      if (ready.isNotEmpty) {
        unawaited(_runPendingQueuedUploads(room.id, ready));
      }
    }
  }

  Future<void> _loadPreviewType() async {
    final chunk = widget.previewChannel;
    if (chunk == null) return;
    final isChannel = await widget.matrixProvider.service.isPublicRoomChannel(
      chunk.roomId,
      forceRefresh: true,
    );
    if (mounted) setState(() => _previewIsChannel = isChannel);
  }

  Future<void> _loadGroupMembers() async {
    if (_room == null) return;

    try {
      final groupService = GroupService(widget.matrixProvider.service);
      final members = await groupService.getGroupMembers(_room!.id);
      if (mounted) {
        setState(() => _groupMembers = members);
      }
    } catch (e) {
      debugPrint('[MatrixChat] Failed to load group members: $e');
    }
  }

  Future<void> _loadOwnRestriction() async {
    if (_room == null || _isDirectRoom || _myUserId.isEmpty) return;

    try {
      final groupService = GroupService(widget.matrixProvider.service);
      final restriction =
          groupService.getMemberRestriction(_room!.id, _myUserId);
      if (mounted) {
        setState(() => _ownRestriction = restriction);
      }
    } catch (e) {
      debugPrint('[MatrixChat] Failed to load own restriction: $e');
    }
  }

  void _checkForMention() {
    final text = _textCtrl.text;
    final cursorPos = _textCtrl.selection.baseOffset;

    if (cursorPos < 0) return;

    // Find the last @ before cursor
    final beforeCursor = text.substring(0, cursorPos);
    final lastAtIndex = beforeCursor.lastIndexOf('@');

    if (lastAtIndex == -1) {
      // No @ found, hide autocomplete
      _setMentionAutocomplete(_MentionAutocompleteState.hidden);
      return;
    }

    // Check if there's a space between @ and cursor
    final afterAt = beforeCursor.substring(lastAtIndex + 1);
    if (afterAt.contains(' ')) {
      // Space found, hide autocomplete
      _setMentionAutocomplete(_MentionAutocompleteState.hidden);
      return;
    }

    // Show autocomplete with query only when the visible state changes.
    _setMentionAutocomplete(_MentionAutocompleteState.visible(afterAt));
  }

  void _setMentionAutocomplete(_MentionAutocompleteState next) {
    final current = _mentionAutocomplete.value;
    if (current.visible == next.visible && current.query == next.query) return;
    _mentionAutocomplete.value = next;
  }

  void _handleTyping(bool isTyping) {
    if (_room == null) return;

    // Cancel existing timer
    _typingTimer?.cancel();

    if (!_appSettings.typingIndicatorsEnabled) {
      _directChatService.sendTypingIndicator(_room!.id, false);
      return;
    }

    if (isTyping) {
      // Send typing indicator
      _directChatService.sendTypingIndicator(_room!.id, true);

      // Set timer to stop typing after 5 seconds
      _typingTimer = Timer(const Duration(seconds: 5), () {
        _directChatService.sendTypingIndicator(_room!.id, false);
      });
    } else {
      // Stop typing immediately
      _directChatService.sendTypingIndicator(_room!.id, false);
    }
  }

  void _listenForTyping() {
    if (_room == null) return;

    _typingSub?.cancel();

    // Listen to room updates for typing indicators
    _typingSub = _room!.onUpdate.stream.listen((_) {
      if (mounted) {
        final typingIndicators = _directChatService.getTypingUsers(_room!);
        final typingUserNames =
            typingIndicators.map((t) => t.displayName).toList();

        if (!listEquals(typingUserNames, _typingUsers)) {
          setState(() {
            _typingUsers = typingUserNames;
          });
        }
      }
    });
  }

  void _insertMention(GroupMember member) {
    final text = _textCtrl.text;
    final cursorPos = _textCtrl.selection.baseOffset;

    if (cursorPos < 0) return;

    // Find the last @ before cursor
    final beforeCursor = text.substring(0, cursorPos);
    final lastAtIndex = beforeCursor.lastIndexOf('@');

    if (lastAtIndex == -1) return;

    // Replace from @ to cursor with mention
    final beforeMention = text.substring(0, lastAtIndex);
    final afterCursor = text.substring(cursorPos);
    final mention = '@${member.displayName} ';

    final newText = beforeMention + mention + afterCursor;
    final newCursorPos = beforeMention.length + mention.length;

    _textCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    _setMentionAutocomplete(_MentionAutocompleteState.hidden);
  }

  Future<void> _loadTimeline() async {
    if (_room == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final timeline = await widget.matrixProvider.service.getTimeline(_room!.id);
    if (timeline != null) {
      unawaited(_indexSharedMediaTimeline(timeline));
    }
    if (mounted) {
      setState(() {
        _timeline = timeline;
        _loading = false;
        _historyExhausted = timeline == null;
      });
      await _loadOlderMessages(
        historyCount: 100,
        preserveScroll: false,
        autoScrollAfterLoad: true,
      );
      _scrollToBottom();
      _openInitialHighlightedMessage();
      _scheduleMarkRoomAsRead();
      _loadPinnedMessages();
      _eventSub = widget.matrixProvider.service.onEvent.listen((update) {
        if (update.roomID == _room!.id && mounted) {
          final shouldAutoScroll = _shouldAutoScrollForTimelineUpdate();
          if (update.type == EventUpdateType.timeline) {
            final timeline = _timeline;
            if (timeline != null) {
              _scheduleSharedMediaIndex(timeline);
              if (_appSettings.autoDownloadMedia) {
                _preloadVideoThumbnails(timeline);
              }
            }
            _scheduleTimelineUiRefresh(shouldAutoScroll: shouldAutoScroll);
            _scheduleMarkRoomAsRead();
          } else {
            _scheduleStateRefresh();
          }
          // Reload pinned messages if state changed
          if (update.type == EventUpdateType.state) {
            _scheduleStateRefresh(loadStateData: true);
          }
        }
      });

      // Pre-load video thumbnails in the background so they're ready
      // before the user scrolls to them — eliminates the loading flash.
      if (timeline != null && _appSettings.autoDownloadMedia) {
        _preloadVideoThumbnails(timeline);
      }
    }
  }

  void _handleChatScroll() {
    _handlePinnedBannerScroll();
    _maybeLoadOlderMessages();
    _syncJumpButtonWithScrollPosition();
  }

  void _scheduleTimelineUiRefresh({required bool shouldAutoScroll}) {
    if (shouldAutoScroll) {
      _pendingTimelineAutoScroll = true;
    } else if (!_loadingHistory) {
      _pendingNewMessagesBelow = (_pendingNewMessagesBelow + 1).clamp(0, 999);
    }

    if (_timelineUiRefreshScheduled) return;
    _timelineUiRefreshScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _timelineUiRefreshScheduled = false;
        return;
      }

      final shouldScroll = _pendingTimelineAutoScroll;
      final newMessagesBelow = _pendingNewMessagesBelow;
      _pendingTimelineAutoScroll = false;
      _pendingNewMessagesBelow = 0;
      _timelineUiRefreshScheduled = false;

      if (shouldScroll) {
        if (_showJumpToLatestButton || _newMessagesBelowCount > 0) {
          setState(_clearNewMessagesBelow);
        } else {
          setState(() {});
        }
        _scrollToBottom();
        return;
      }

      if (_loadingHistory) {
        setState(() {});
        return;
      }

      setState(() {
        _showJumpToLatestButton = true;
        _newMessagesBelowCount =
            (_newMessagesBelowCount + newMessagesBelow).clamp(0, 999);
      });
    });
  }

  void _scheduleStateRefresh({bool loadStateData = false}) {
    if (loadStateData) {
      _stateRefreshDebounce?.cancel();
      _stateRefreshDebounce =
          Timer(const Duration(milliseconds: 200), () async {
        if (!mounted) return;
        await _loadPinnedMessages();
        await _loadOwnRestriction();
        if (mounted) setState(() {});
      });
      return;
    }

    if (_stateRefreshDebounce?.isActive ?? false) return;
    _stateRefreshDebounce = Timer(const Duration(milliseconds: 16), () {
      if (mounted) setState(() {});
    });
  }

  void _maybeLoadOlderMessages() {
    if (!_scrollCtrl.hasClients ||
        _loadingHistory ||
        _historyExhausted ||
        _timeline == null) {
      return;
    }
    if (_scrollCtrl.offset <= 120) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages({
    int historyCount = 50,
    bool preserveScroll = true,
    bool autoScrollAfterLoad = false,
  }) async {
    final timeline = _timeline;
    if (timeline == null ||
        _loadingHistory ||
        _historyExhausted ||
        !timeline.canRequestHistory) {
      return;
    }

    final beforeEventCount = timeline.events.length;
    final hadScrollPosition = _scrollCtrl.hasClients;
    final beforeOffset = hadScrollPosition ? _scrollCtrl.offset : 0.0;
    final beforeMax =
        hadScrollPosition ? _scrollCtrl.position.maxScrollExtent : 0.0;

    if (mounted) setState(() => _loadingHistory = true);
    try {
      await timeline.requestHistory(historyCount: historyCount);
      final loadedAny = timeline.events.length > beforeEventCount;
      unawaited(
        _indexSharedMediaTimeline(
          timeline,
          historyComplete: !loadedAny || !timeline.canRequestHistory,
        ),
      );
      if (!mounted) return;
      setState(() {
        _historyExhausted = !loadedAny || !timeline.canRequestHistory;
      });

      if (autoScrollAfterLoad) {
        _scrollToBottom();
      } else if (preserveScroll && hadScrollPosition) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollCtrl.hasClients) return;
          final afterMax = _scrollCtrl.position.maxScrollExtent;
          final target = (beforeOffset + afterMax - beforeMax).clamp(
            _scrollCtrl.position.minScrollExtent,
            _scrollCtrl.position.maxScrollExtent,
          );
          _scrollCtrl.jumpTo(target);
        });
      }

      if (_appSettings.autoDownloadMedia) {
        _preloadVideoThumbnails(timeline);
      }
    } catch (e) {
      debugPrint('[Timeline] Failed to load older room history: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _scheduleMarkRoomAsRead() {
    _readMarkerDebounce?.cancel();
    _readMarkerDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _markRoomAsRead();
    });
  }

  Future<void> _markRoomAsRead() async {
    final room = _room;
    final lastEventId = room?.lastEvent?.eventId;
    if (room == null || lastEventId == null || lastEventId.isEmpty) return;

    try {
      await room.setReadMarker(
        lastEventId,
        mRead: lastEventId,
        public: _appSettings.readReceiptsEnabled,
      );
      room.notificationCount = 0;
      widget.matrixProvider.refreshRooms();
    } catch (e) {
      debugPrint('[MatrixChat] Failed to mark room as read: $e');
    }
  }

  Future<void> _loadPinnedMessages() async {
    if (_room == null) return;

    final pinnedState = _room!.getState(EventTypes.RoomPinnedEvents);
    if (pinnedState == null) {
      setState(() => _pinnedEvents = []);
      return;
    }

    final pinnedContent = pinnedState.content['pinned'];
    final pinnedEventIds = pinnedContent is List
        ? List<String>.from(pinnedContent.cast<String>())
        : <String>[];

    if (pinnedEventIds.isEmpty) {
      setState(() => _pinnedEvents = []);
      return;
    }

    final events = <Event>[];
    final staleEventIds = <String>[];
    for (final eventId in pinnedEventIds) {
      try {
        final event = await _room!.getEventById(eventId);
        if (event != null && !event.redacted) {
          events.add(event);
        } else {
          staleEventIds.add(eventId);
        }
      } catch (e) {
        staleEventIds.add(eventId);
        debugPrint('[PinnedMessages] Failed to fetch event $eventId: $e');
      }
    }

    if (mounted) {
      setState(() {
        _pinnedEvents = events;
        _pinnedBannerIndex = null;
      });
    }

    if (staleEventIds.isNotEmpty) {
      unawaited(_cleanupStalePinnedMessages(staleEventIds));
    }
  }

  Future<void> _cleanupStalePinnedMessages(List<String> eventIds) async {
    if (_room == null || !_canPinMessages()) return;

    final groupService = GroupService(widget.matrixProvider.service);
    for (final eventId in eventIds) {
      try {
        await groupService.unpinMessage(_room!.id, eventId);
      } catch (e) {
        debugPrint('[PinnedMessages] Failed to remove stale pin $eventId: $e');
      }
    }
  }

  List<Event> _orderedPinnedEvents() {
    if (_pinnedEvents.isEmpty) return const [];

    final visible = _visibleMessages();
    final indexById = <String, int>{
      for (var i = 0; i < visible.length; i++) visible[i].eventId: i,
    };

    final ordered = List<Event>.from(_pinnedEvents);
    ordered.sort((a, b) {
      final aIndex = indexById[a.eventId];
      final bIndex = indexById[b.eventId];
      if (aIndex != null && bIndex != null) {
        return aIndex.compareTo(bIndex);
      }
      if (aIndex != null) return -1;
      if (bIndex != null) return 1;
      return a.originServerTs.compareTo(b.originServerTs);
    });

    return ordered;
  }

  int _currentPinnedBannerIndex(List<Event> orderedPinnedEvents) {
    if (orderedPinnedEvents.isEmpty) return 0;
    final index = _pinnedBannerIndex;
    if (index == null) return orderedPinnedEvents.length - 1;
    return index.clamp(0, orderedPinnedEvents.length - 1);
  }

  void _handlePinnedBannerScroll() {
    if (_isJumpingToPinnedMessage ||
        _pinnedEvents.length < 2 ||
        !_scrollCtrl.hasClients) {
      if (_scrollCtrl.hasClients) {
        _lastPinnedScrollOffset = _scrollCtrl.offset;
      }
      return;
    }

    final offset = _scrollCtrl.offset;
    final scrollingDown = offset > _lastPinnedScrollOffset;
    _lastPinnedScrollOffset = offset;
    if (!scrollingDown) return;

    final orderedPinnedEvents = _orderedPinnedEvents();
    if (orderedPinnedEvents.length < 2) return;

    final currentIndex = _currentPinnedBannerIndex(orderedPinnedEvents);
    if (currentIndex >= orderedPinnedEvents.length - 1) return;

    if ((offset - _lastPinnedBannerScrollSyncOffset).abs() < 96) return;

    setState(() {
      _pinnedBannerIndex = currentIndex + 1;
      _lastPinnedBannerScrollSyncOffset = offset;
    });
  }

  Future<void> _jumpToPinnedMessage() async {
    final orderedPinnedEvents = _orderedPinnedEvents();
    if (orderedPinnedEvents.isEmpty) return;

    final index = _currentPinnedBannerIndex(orderedPinnedEvents);
    final event = orderedPinnedEvents[index];
    _isJumpingToPinnedMessage = true;
    try {
      await _scrollToAndHighlightMessage(event.eventId);
    } finally {
      _isJumpingToPinnedMessage = false;
    }

    if (!mounted) return;
    setState(() {
      _pinnedBannerIndex = index > 0 ? index - 1 : 0;
      if (_scrollCtrl.hasClients) {
        _lastPinnedScrollOffset = _scrollCtrl.offset;
        _lastPinnedBannerScrollSyncOffset = _scrollCtrl.offset;
      }
    });
  }

  void _preloadVideoThumbnails(Timeline timeline) {
    var queued = 0;
    for (final event in timeline.events) {
      if (event.type != EventTypes.Message ||
          event.messageType != MessageTypes.Video) {
        continue;
      }

      final eventId = event.eventId;
      if (eventId.isEmpty ||
          _preloadedVideoThumbnailEventIds.contains(eventId) ||
          MediaHandler.getCachedThumbnail(eventId) != null) {
        continue;
      }

      _preloadedVideoThumbnailEventIds.add(eventId);
      _mediaHandler.loadVideoThumbnail(event).ignore();

      queued += 1;
      if (queued >= 12) break;
    }
  }

  void _scheduleSharedMediaIndex(Timeline timeline) {
    _sharedMediaIndexDebounce?.cancel();
    _sharedMediaIndexDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        unawaited(_indexSharedMediaTimeline(timeline));
      }
    });
  }

  Future<void> _indexSharedMediaTimeline(
    Timeline timeline, {
    bool historyComplete = false,
  }) async {
    final room = _room;
    final ownerUserId = widget.matrixProvider.userId;
    if (room == null || ownerUserId == null || ownerUserId.isEmpty) return;
    try {
      await SharedMediaIndexService.instance.indexTimeline(
        ownerUserId: ownerUserId,
        room: room,
        timeline: timeline,
        historyComplete: historyComplete,
      );
    } catch (e) {
      debugPrint('[SharedMediaIndex] Failed to index chat timeline: $e');
    }
  }

  void _scrollToBottom({bool animate = false}) {
    if (_scrollToBottomScheduled) return;
    _scrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomScheduled = false;
      if (_scrollCtrl.hasClients) {
        final target = _scrollCtrl.position.maxScrollExtent;
        if ((_scrollCtrl.offset - target).abs() <= 1) return;
        if (animate) {
          unawaited(
            _scrollCtrl
                .animateTo(
              target,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            )
                .then((_) {
              if (!_scrollCtrl.hasClients) return;
              final finalTarget = _scrollCtrl.position.maxScrollExtent;
              if ((_scrollCtrl.offset - finalTarget).abs() > 1) {
                _scrollCtrl.jumpTo(finalTarget);
              }
            }),
          );
        } else {
          _scrollCtrl.jumpTo(target);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollCtrl.hasClients || !_isNearBottom) return;
            final finalTarget = _scrollCtrl.position.maxScrollExtent;
            if ((_scrollCtrl.offset - finalTarget).abs() > 1) {
              _scrollCtrl.jumpTo(finalTarget);
            }
          });
        }
      }
    });
  }

  bool get _isNearBottom {
    if (!_scrollCtrl.hasClients) return true;
    return _scrollCtrl.position.extentAfter <= _jumpToLatestHideExtent;
  }

  bool _shouldAutoScrollForTimelineUpdate() {
    if (_loadingHistory) return false;
    return _isNearBottom;
  }

  void _clearNewMessagesBelow() {
    _showJumpToLatestButton = false;
    _newMessagesBelowCount = 0;
  }

  void _syncJumpButtonWithScrollPosition() {
    if (!_scrollCtrl.hasClients) return;

    final extentAfter = _scrollCtrl.position.extentAfter;
    final shouldShow = _showJumpToLatestButton
        ? extentAfter > _jumpToLatestHideExtent
        : extentAfter > _jumpToLatestShowExtent;
    if (shouldShow == _showJumpToLatestButton) {
      if (!shouldShow && _newMessagesBelowCount > 0) {
        setState(() => _newMessagesBelowCount = 0);
      }
      return;
    }
    setState(() {
      _showJumpToLatestButton = shouldShow;
      if (!shouldShow) {
        _newMessagesBelowCount = 0;
      }
    });
  }

  void _jumpToLatestMessages() {
    if (mounted && (_showJumpToLatestButton || _newMessagesBelowCount > 0)) {
      setState(_clearNewMessagesBelow);
    }
    _scrollToBottom(animate: true);
    _markRoomAsRead();
  }

  Widget _buildJumpToLatestButton() {
    final countLabel =
        _newMessagesBelowCount >= 999 ? '999+' : '$_newMessagesBelowCount';
    final visible = _showJumpToLatestButton;

    return Positioned(
      right: 18,
      bottom: 78,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 4),
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.22),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _jumpToLatestMessages,
                child: SizedBox(
                  width: 54,
                  height: 62,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF1B2A36).withValues(alpha: 0.98),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: kBlack.withValues(alpha: 0.38),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: kWhite,
                          size: 34,
                        ),
                      ),
                      if (_newMessagesBelowCount > 0)
                        Positioned(
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4B9CE2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              countLabel,
                              style: GoogleFonts.inter(
                                color: kWhite,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryLoadingIndicator() {
    return const OldMessagesLoadingIndicator();
  }

  Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _room == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }
    if (!_ensureRoomActionAllowed(XmoRoomPermission.sendMessages) ||
        !_ensureSlowModeAllowed()) {
      return;
    }
    final replyToEvent = _replyToEvent;
    final privateReplyDraft = _privateReplyDraft;
    _textCtrl.clear();
    setState(() {
      _replyToEvent = null;
      _privateReplyDraft = null;
    });
    _scrollToBottom();

    try {
      // Send reply if replying to a message
      if (replyToEvent != null) {
        await _room!.sendTextEvent(text, inReplyTo: replyToEvent);
      } else if (privateReplyDraft != null) {
        await _room!.sendEvent({
          'msgtype': MessageTypes.Text,
          'body': text,
          'com.xmo.private_reply': privateReplyDraft.toJson(),
        });
      } else {
        await widget.matrixProvider.sendMessage(_room!.id, text);
      }
    } catch (e) {
      if (!mounted) return;
      if (_textCtrl.text.isEmpty) {
        _textCtrl.text = text;
        _textCtrl.selection = TextSelection.collapsed(offset: text.length);
      }
      setState(() {
        _replyToEvent = replyToEvent;
        _privateReplyDraft = privateReplyDraft;
      });
      _showSnackBar('Failed to send message: $e');
    }
  }

  void _showComposerEmojiPicker() {
    if (!_canSendMessages) return;

    void switchToKeyboard() {
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocusNode.requestFocus();
      });
    }

    ReactionPicker.show(
      context,
      (emoji) {
        final value = _textCtrl.value;
        final selection = value.selection;
        final start = selection.isValid ? selection.start : value.text.length;
        final end = selection.isValid ? selection.end : value.text.length;
        final updatedText = value.text.replaceRange(start, end, emoji);
        final cursorOffset = start + emoji.length;

        _textCtrl.value = TextEditingValue(
          text: updatedText,
          selection: TextSelection.collapsed(offset: cursorOffset),
        );
      },
      closeOnSelection: false,
      composer: ChatInputBar(
        textController: _textCtrl,
        emojiButtonIcon: Icons.keyboard_alt_outlined,
        uploading: _isUploadBusy,
        recording: false,
        enabled: _canSendMessages,
        disabledText: _isReadOnlyRestricted
            ? 'Read-only mode'
            : 'You cannot send messages',
        onSend: () {
          Navigator.pop(context);
          _sendMessage();
        },
        onShowEmojiPicker: switchToKeyboard,
        onTextFieldTap: switchToKeyboard,
        onShowAttachmentSheet: () {
          Navigator.pop(context);
          _showAttachmentSheet();
        },
        onStartRecording: () {
          Navigator.pop(context);
          _startAudioRecording();
        },
        onCancelRecording: _cancelAudioRecording,
        onToggleRecordingPause: _toggleAudioRecordingPause,
        onStopAndSendRecording: _stopAndSendAudioRecording,
      ),
    );
  }

  Future<void> _startAudioRecording() async {
    if (_room == null || _uploading || _recording) return;
    if (kIsWeb) {
      _showSnackBar('Voice recording is not available in the web build yet.');
      return;
    }
    if (!_ensureRoomActionAllowed(XmoRoomPermission.sendMedia) ||
        !_ensureSlowModeAllowed()) {
      return;
    }

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showSnackBar('Microphone permission is required.');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${tempDir.path}/xmo_voice_$timestamp.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _recordingStartedAt = DateTime.now();
      _recordingAccumulatedDuration = Duration.zero;
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final startedAt = _recordingStartedAt;
        if (startedAt == null || !mounted) return;
        setState(() {
          _recordingDuration = _recordingAccumulatedDuration +
              DateTime.now().difference(startedAt);
        });
      });
      _amplitudeSub?.cancel();
      _amplitudeSub = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 90))
          .listen(_handleRecordingAmplitude);

      setState(() {
        _recording = true;
        _recordingPaused = false;
        _recordingDuration = Duration.zero;
        _recordingWaveform = const [];
        _lastRecordingWaveformUiUpdate = null;
      });
    } catch (e) {
      _showSnackBar('Failed to start recording: $e');
    }
  }

  void _handleRecordingAmplitude(Amplitude amplitude) {
    if (!mounted || !_recording || _recordingPaused) return;

    final now = DateTime.now();
    final lastUpdate = _lastRecordingWaveformUiUpdate;
    if (lastUpdate != null &&
        now.difference(lastUpdate) < const Duration(milliseconds: 160)) {
      return;
    }

    final normalized =
        ((amplitude.current + 45) / 45).clamp(0.08, 1.0).toDouble();
    final next = List<double>.from(_recordingWaveform)..add(normalized);
    if (next.length > 56) {
      next.removeRange(0, next.length - 56);
    }
    setState(() {
      _recordingWaveform = next;
      _lastRecordingWaveformUiUpdate = now;
    });
  }

  Future<void> _toggleAudioRecordingPause() async {
    if (!_recording) return;

    try {
      if (_recordingPaused) {
        await _audioRecorder.resume();
        _recordingStartedAt = DateTime.now();
        setState(() => _recordingPaused = false);
      } else {
        await _audioRecorder.pause();
        final startedAt = _recordingStartedAt;
        if (startedAt != null) {
          _recordingAccumulatedDuration += DateTime.now().difference(startedAt);
        }
        _recordingStartedAt = null;
        setState(() {
          _recordingPaused = true;
          _recordingDuration = _recordingAccumulatedDuration;
        });
      }
    } catch (e) {
      _showSnackBar('Could not ${_recordingPaused ? 'resume' : 'pause'}: $e');
    }
  }

  Future<void> _cancelAudioRecording() async {
    if (!_recording) return;
    try {
      await _audioRecorder.stop();
    } catch (_) {
      // Recorder may already be stopped by the platform.
    }
    _recordingTimer?.cancel();
    _amplitudeSub?.cancel();
    _recordingStartedAt = null;
    _recordingAccumulatedDuration = Duration.zero;
    if (mounted) {
      setState(() {
        _recording = false;
        _recordingPaused = false;
        _recordingDuration = Duration.zero;
        _recordingWaveform = const [];
      });
    }
  }

  Future<void> _stopAndSendAudioRecording() async {
    final room = _room;
    if (!_recording || room == null) return;

    final duration = _recordingDuration;
    _recordingTimer?.cancel();
    _amplitudeSub?.cancel();
    _recordingStartedAt = null;
    _recordingAccumulatedDuration = Duration.zero;

    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (e) {
      _showSnackBar('Failed to stop recording: $e');
    }

    if (mounted) {
      setState(() {
        _recording = false;
        _recordingPaused = false;
        _recordingDuration = Duration.zero;
        _recordingWaveform = const [];
      });
    }

    if (path == null || path.isEmpty) return;

    if (duration.inMilliseconds < 500) {
      _showSnackBar('Recording is too short.');
      return;
    }

    try {
      final bytes = await readAudioFileBytes(path);
      if (bytes.isEmpty) {
        _showSnackBar('Recording is empty.');
        return;
      }

      await _sendAudioWithPending(
        room.id,
        bytes: bytes,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        mimeType: 'audio/mp4',
        durationMs: duration.inMilliseconds,
        isVoiceMessage: true,
      );
    } catch (e) {
      if (e is! MatrixUploadCancelledException) {
        _showSnackBar('Failed to send voice message: $e');
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: kDarkerGrey,
      ),
    );
  }

  void _setReplyTo(Event event) {
    if (!_ensureStableMessageActionTarget(event)) return;
    setState(() {
      _replyToEvent = event;
      _privateReplyDraft = null;
    });
  }

  void _cancelReply() {
    setState(() => _replyToEvent = null);
  }

  void _cancelPrivateReply() {
    setState(() => _privateReplyDraft = null);
  }

  Future<void> _joinPreviewChannel() async {
    final chunk = widget.previewChannel;
    if (chunk == null) return;
    try {
      setState(() => _loading = true);
      final isChannel = await widget.matrixProvider.service.isPublicRoomChannel(
        chunk.roomId,
        forceRefresh: true,
      );
      await widget.matrixProvider.service.joinRoom(chunk.roomId);
      widget.matrixProvider.refreshRooms();
      if (mounted) {
        final room = widget.matrixProvider.service.getRoomById(chunk.roomId);
        if (room != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MatrixChatScreen(
                room: room,
                matrixProvider: widget.matrixProvider,
              ),
            ),
          );
        } else {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Joined ${isChannel ? 'channel' : 'group'} successfully!'),
            backgroundColor: kLimeGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to join: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _setUploading(bool value) {
    if (mounted) setState(() => _uploading = value);
  }

  String _addPendingUpload(_PendingUpload upload) {
    if (mounted) {
      setState(() => _pendingUploads.add(upload));
      _scrollToBottom();
    }
    return upload.id;
  }

  void _removePendingUpload(String id) {
    if (!mounted) return;
    _pendingUploadProgressUiUpdates.remove(id);
    setState(() => _pendingUploads.removeWhere((upload) => upload.id == id));
  }

  void _cancelPendingUpload(String id) {
    _cancelledPendingUploadIds.add(id);
    unawaited(_transferQueue.cancel(id));
    _removePendingUpload(id);
    _setUploading(false);
  }

  bool _isPendingUploadCancelled(String id) {
    return _cancelledPendingUploadIds.contains(id);
  }

  void _updatePendingUploadProgress(
    String id,
    int uploadedBytes,
    int totalBytes,
  ) {
    if (!mounted) return;
    final index = _pendingUploads.indexWhere((upload) => upload.id == id);
    if (index == -1) return;

    _applyPendingUploadProgress(
      _pendingUploads[index],
      uploadedBytes: uploadedBytes,
      totalBytes: totalBytes,
    );
  }

  void _applyPendingUploadProgress(
    _PendingUpload upload, {
    required int uploadedBytes,
    required int totalBytes,
  }) {
    final id = upload.id;
    final clampedTotalBytes = totalBytes < 0 ? 0 : totalBytes;
    final clampedUploadedBytes = clampedTotalBytes > 0
        ? uploadedBytes.clamp(0, clampedTotalBytes).toInt()
        : uploadedBytes.clamp(0, uploadedBytes < 0 ? 0 : uploadedBytes).toInt();
    final previousTotalBytes = upload.totalBytes;
    final previousUploadedBytes = upload.uploadedBytes;
    if (previousTotalBytes == clampedTotalBytes &&
        previousUploadedBytes == clampedUploadedBytes) {
      return;
    }

    final previousProgress = previousTotalBytes > 0
        ? previousUploadedBytes / previousTotalBytes
        : 0.0;
    final nextProgress =
        clampedTotalBytes > 0 ? clampedUploadedBytes / clampedTotalBytes : 0.0;
    final isComplete =
        clampedTotalBytes > 0 && clampedUploadedBytes >= clampedTotalBytes;
    final isFirstProgress = previousUploadedBytes == 0;
    final progressChangedEnough =
        (nextProgress - previousProgress).abs() >= 0.02;
    final now = DateTime.now();
    final lastUpdate = _pendingUploadProgressUiUpdates[id];
    final enoughTimePassed = lastUpdate == null ||
        now.difference(lastUpdate) >= const Duration(milliseconds: 160);

    upload.uploadedBytes = clampedUploadedBytes;
    upload.totalBytes = clampedTotalBytes;

    if (!isComplete &&
        !isFirstProgress &&
        !progressChangedEnough &&
        !enoughTimePassed) {
      return;
    }

    _pendingUploadProgressUiUpdates[id] = now;
    unawaited(_transferQueue.updateProgress(
      id,
      clampedUploadedBytes,
      clampedTotalBytes,
    ));
    _scheduleUploadProgressRepaint();
  }

  void _scheduleUploadProgressRepaint() {
    if (!mounted || _uploadProgressFrameScheduled) return;
    _uploadProgressFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _uploadProgressFrameScheduled = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _ensureTransferJob(
    String roomId,
    _PendingUpload upload,
  ) async {
    if (upload.transferJobId != null) return;
    final job = await _transferQueue.createUploadJob(
      id: upload.id,
      roomId: roomId,
      bytes: upload.bytes,
      thumbnailBytes: upload.thumbnailBytes,
      fileName: upload.fileName,
      mimeType: upload.mimeType,
      kind: _transferKindFor(upload),
    );
    upload.transferJobId = job.id;
  }

  TransferKind _transferKindFor(_PendingUpload upload) {
    if (upload.isVideo) return TransferKind.video;
    if (upload.isAudio) return TransferKind.audio;
    if (upload.isFile) return TransferKind.file;
    return TransferKind.photo;
  }

  Future<void> _runSinglePendingMediaUpload(
    String roomId,
    _PendingUpload upload, {
    String caption = '',
  }) async {
    _setUploading(true);
    try {
      await _sendPendingUpload(roomId, upload, caption: caption);
      _removePendingUpload(upload.id);
      await _transferQueue.remove(upload.id);
      _cancelledPendingUploadIds.remove(upload.id);
    } catch (e) {
      if (e is MatrixUploadCancelledException ||
          _isPendingUploadCancelled(upload.id) ||
          upload.cancelled) {
        await _transferQueue.cancel(upload.id);
        _removePendingUpload(upload.id);
      } else if (mounted) {
        setState(() {
          upload.failed = true;
          upload.error = e.toString();
        });
        await _transferQueue.markFailed(upload.id, e);
        _schedulePendingUploadRetry(roomId, upload);
        _showSnackBar('Failed to send media: $e');
      }
    } finally {
      _setUploading(false);
      _scrollToBottom();
    }
  }

  Future<void> _sendPendingUpload(
    String roomId,
    _PendingUpload upload, {
    String caption = '',
  }) async {
    if (upload.isVideo) {
      await upload.previewHydration;
    }

    await _ensureTransferJob(roomId, upload);
    final claimed = await _transferQueue.markRunning(upload.id);
    if (!claimed) {
      debugPrint('[TransferQueue] Upload ${upload.id} is already running');
      return;
    }
    if (mounted) {
      setState(() {
        upload.started = true;
        upload.failed = false;
        upload.error = null;
      });
    }

    bool isCancelled() {
      return _isPendingUploadCancelled(upload.id) ||
          upload.cancelled ||
          _transferQueue.isCancelled(upload.id);
    }

    if (upload.isVideo) {
      await _mediaHandler.sendVideoBytes(
        roomId,
        _setUploading,
        bytes: upload.bytes,
        fileName: upload.fileName,
        mimeType: upload.mimeType,
        caption: caption,
        precomputedThumbnailBytes: upload.thumbnailBytes,
        precomputedVideoWidth: upload.width,
        precomputedVideoHeight: upload.height,
        precomputedDurationMs: upload.durationMs,
        onUploadProgress: (uploadedBytes, totalBytes) =>
            _updatePendingUploadProgress(
          upload.id,
          uploadedBytes,
          totalBytes,
        ),
        isCancelled: isCancelled,
        rethrowErrors: true,
      );
    } else if (upload.isAudio) {
      await widget.matrixProvider.service.sendAudio(
        roomId: roomId,
        audioBytes: upload.bytes,
        fileName: upload.fileName,
        mimeType: upload.mimeType,
        durationMs: upload.durationMs ?? 0,
        isVoiceMessage: upload.isVoiceMessage,
        onUploadProgress: (uploadedBytes, totalBytes) =>
            _updatePendingUploadProgress(
          upload.id,
          uploadedBytes,
          totalBytes,
        ),
        isCancelled: isCancelled,
      );
    } else if (upload.isFile) {
      await widget.matrixProvider.service.sendFileWithProgress(
        roomId: roomId,
        bytes: upload.bytes,
        fileName: upload.fileName,
        mimeType: upload.mimeType,
        onUploadProgress: (uploadedBytes, totalBytes) =>
            _updatePendingUploadProgress(
          upload.id,
          uploadedBytes,
          totalBytes,
        ),
        isCancelled: isCancelled,
      );
    } else {
      await _mediaHandler.sendPhotoBytes(
        roomId,
        _setUploading,
        bytes: upload.bytes,
        fileName: upload.fileName,
        mimeType: upload.mimeType,
        caption: caption,
        onUploadProgress: (uploadedBytes, totalBytes) =>
            _updatePendingUploadProgress(
          upload.id,
          uploadedBytes,
          totalBytes,
        ),
        isCancelled: isCancelled,
        rethrowErrors: true,
      );
    }
    await _transferQueue.markCompleted(upload.id);
  }

  Future<void> _sendPhotoWithPending(
    String roomId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String caption,
  }) async {
    final pendingId = _addPendingUpload(
      _PendingUpload(
        id: 'photo_${DateTime.now().microsecondsSinceEpoch}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isVideo: false,
        totalBytes: bytes.length,
        createdAt: DateTime.now(),
      ),
    );

    final upload = _pendingUploads.firstWhere((item) => item.id == pendingId);
    upload.previewHydration =
        _hydratePendingUploadPreview(upload, mimeType: mimeType);
    unawaited(upload.previewHydration);
    await _runSinglePendingMediaUpload(
      roomId,
      upload,
      caption: caption,
    );
  }

  Future<Size?> _readImageSize(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  Future<void> _hydratePendingUploadPreview(
    _PendingUpload upload, {
    required String mimeType,
  }) async {
    if (upload.cancelled || upload.completed) return;

    Uint8List? thumbnailBytes;
    int? width;
    int? height;
    int? durationMs;

    if (upload.isVideo) {
      try {
        final metadata =
            await _mediaHandler.readVideoPreviewMetadata(upload.bytes);
        width = metadata?.width;
        height = metadata?.height;
        durationMs = metadata?.durationMs;
      } catch (e) {
        debugPrint('[UploadPreview] Failed to read video metadata: $e');
      }

      try {
        thumbnailBytes = await _mediaHandler.createVideoPreviewThumbnail(
          upload.bytes,
          mimeType,
        );
      } catch (e) {
        debugPrint('[UploadPreview] Failed to create video thumbnail: $e');
      }
    } else if (!upload.isAudio && !upload.isFile) {
      try {
        final imageSize = await _readImageSize(upload.bytes);
        width = imageSize?.width.round();
        height = imageSize?.height.round();
      } catch (e) {
        debugPrint('[UploadPreview] Failed to read image size: $e');
      }
    }

    if (!mounted || upload.cancelled || upload.completed) return;
    upload.thumbnailBytes = thumbnailBytes ?? upload.thumbnailBytes;
    upload.width = width ?? upload.width;
    upload.height = height ?? upload.height;
    upload.durationMs = durationMs ?? upload.durationMs;
    _scheduleUploadPreviewRepaint();
  }

  void _scheduleUploadPreviewRepaint() {
    if (!mounted || _uploadPreviewFrameScheduled) return;
    _uploadPreviewFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _uploadPreviewFrameScheduled = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _sendVideoWithPending(
    String roomId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String caption,
  }) async {
    final pendingId = _addPendingUpload(
      _PendingUpload(
        id: 'video_${DateTime.now().microsecondsSinceEpoch}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isVideo: true,
        totalBytes: bytes.length,
        createdAt: DateTime.now(),
      ),
    );

    final upload = _pendingUploads.firstWhere((item) => item.id == pendingId);
    upload.previewHydration =
        _hydratePendingUploadPreview(upload, mimeType: mimeType);
    unawaited(upload.previewHydration);
    await _runSinglePendingMediaUpload(
      roomId,
      upload,
      caption: caption,
    );
  }

  _PendingUpload _createPendingMediaUpload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required bool isVideo,
  }) {
    final upload = _PendingUpload(
      id: '${isVideo ? 'video' : 'photo'}_${DateTime.now().microsecondsSinceEpoch}',
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      isVideo: isVideo,
      totalBytes: bytes.length,
      createdAt: DateTime.now(),
    );
    upload.previewHydration =
        _hydratePendingUploadPreview(upload, mimeType: mimeType);
    return upload;
  }

  void _startPendingAlbumUpload(String roomId, List<_PendingUpload> uploads) {
    final album = _PendingAlbumUpload(
      id: 'album_${DateTime.now().microsecondsSinceEpoch}',
      uploads: uploads,
      createdAt: DateTime.now(),
    );

    if (mounted) {
      setState(() => _pendingAlbumUploads.add(album));
      _scrollToBottom();
    }

    for (final upload in uploads) {
      unawaited(upload.previewHydration);
    }

    unawaited(_runPendingAlbumUpload(roomId, album));
  }

  Future<void> _runPendingAlbumUpload(
    String roomId,
    _PendingAlbumUpload album,
  ) async {
    while (!album.cancelled && album.uploads.isNotEmpty) {
      final nextIndex = album.uploads.indexWhere(
        (upload) => !upload.cancelled && !upload.completed && !upload.failed,
      );
      if (nextIndex == -1) break;
      final upload = album.uploads[nextIndex];

      if (mounted) {
        setState(() {
          album.currentUploadId = upload.id;
          upload.started = true;
        });
      }

      try {
        if (upload.isVideo) {
          await upload.previewHydration;
        }
        await _ensureTransferJob(roomId, upload);
        final claimed = await _transferQueue.markRunning(upload.id);
        if (!claimed) {
          debugPrint('[TransferQueue] Upload ${upload.id} is already running');
          continue;
        }
        if (upload.isVideo) {
          await _mediaHandler.sendVideoBytes(
            roomId,
            _setUploading,
            bytes: upload.bytes,
            fileName: upload.fileName,
            mimeType: upload.mimeType,
            caption: '',
            precomputedThumbnailBytes: upload.thumbnailBytes,
            precomputedVideoWidth: upload.width,
            precomputedVideoHeight: upload.height,
            precomputedDurationMs: upload.durationMs,
            onUploadProgress: (uploadedBytes, totalBytes) =>
                _updatePendingAlbumUploadProgress(
              album.id,
              upload.id,
              uploadedBytes,
              totalBytes,
            ),
            isCancelled: () =>
                album.cancelled ||
                upload.cancelled ||
                _transferQueue.isCancelled(upload.id),
            rethrowErrors: true,
          );
        } else {
          await _mediaHandler.sendPhotoBytes(
            roomId,
            _setUploading,
            bytes: upload.bytes,
            fileName: upload.fileName,
            mimeType: upload.mimeType,
            caption: '',
            onUploadProgress: (uploadedBytes, totalBytes) =>
                _updatePendingAlbumUploadProgress(
              album.id,
              upload.id,
              uploadedBytes,
              totalBytes,
            ),
            isCancelled: () =>
                album.cancelled ||
                upload.cancelled ||
                _transferQueue.isCancelled(upload.id),
            rethrowErrors: true,
          );
        }

        if (!album.cancelled && !upload.cancelled && mounted) {
          await _transferQueue.markCompleted(upload.id);
          setState(() {
            if (upload.totalBytes <= 0 ||
                upload.uploadedBytes >= upload.totalBytes) {
              upload.completed = true;
              upload.uploadedBytes = upload.totalBytes;
              _pendingUploadProgressUiUpdates.remove(upload.id);
            } else {
              upload.failed = true;
            }
          });
        }
      } catch (e) {
        if (e is MatrixUploadCancelledException ||
            album.cancelled ||
            upload.cancelled) {
          await _transferQueue.cancel(upload.id);
          break;
        }
        await _transferQueue.markFailed(upload.id, e);
        if (mounted) {
          setState(() {
            upload.failed = true;
            upload.error = e.toString();
          });
        }
        _showSnackBar('Failed to send media: $e');
        break;
      }
    }

    if (!mounted) return;
    final finished = album.uploads.every(
      (upload) => upload.completed || upload.cancelled || upload.failed,
    );
    if (finished && !album.cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
    }
    setState(() {
      if (album.cancelled || finished || album.uploads.isEmpty) {
        _pendingAlbumUploads.removeWhere((pending) => pending.id == album.id);
        _pendingUploadProgressUiUpdates.removeWhere(
          (id, _) => album.uploads.any((upload) => upload.id == id),
        );
      }
      _uploading = false;
    });
    _scrollToBottom();
  }

  void _updatePendingAlbumUploadProgress(
    String albumId,
    String uploadId,
    int uploadedBytes,
    int totalBytes,
  ) {
    if (!mounted) return;
    final albumIndex =
        _pendingAlbumUploads.indexWhere((pending) => pending.id == albumId);
    if (albumIndex == -1) return;
    final album = _pendingAlbumUploads[albumIndex];
    final uploadIndex = album.uploads
        .indexWhere((pendingUpload) => pendingUpload.id == uploadId);
    if (uploadIndex == -1) return;
    _applyPendingUploadProgress(
      album.uploads[uploadIndex],
      uploadedBytes: uploadedBytes,
      totalBytes: totalBytes,
    );
  }

  Future<void> _sendAudioWithPending(
    String roomId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int durationMs,
    required bool isVoiceMessage,
  }) async {
    final pendingId = _addPendingUpload(
      _PendingUpload(
        id: 'audio_${DateTime.now().microsecondsSinceEpoch}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isVideo: false,
        isAudio: true,
        isVoiceMessage: isVoiceMessage,
        totalBytes: bytes.length,
        createdAt: DateTime.now(),
        durationMs: durationMs,
      ),
    );

    final upload = _pendingUploads.firstWhere((item) => item.id == pendingId);
    await _runSinglePendingMediaUpload(roomId, upload);
  }

  _PendingUpload _createPendingAudioUpload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int durationMs,
  }) {
    return _PendingUpload(
      id: 'audio_${DateTime.now().microsecondsSinceEpoch}_${bytes.length}',
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      isVideo: false,
      isAudio: true,
      isVoiceMessage: false,
      totalBytes: bytes.length,
      createdAt: DateTime.now(),
      durationMs: durationMs,
    );
  }

  _PendingUpload _createPendingFileUpload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) {
    return _PendingUpload(
      id: 'file_${DateTime.now().microsecondsSinceEpoch}_${bytes.length}',
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      isVideo: false,
      isFile: true,
      totalBytes: bytes.length,
      createdAt: DateTime.now(),
    );
  }

  void _startPendingQueuedUploads(String roomId, List<_PendingUpload> uploads) {
    if (uploads.isEmpty) return;
    if (mounted) {
      setState(() => _pendingUploads.addAll(uploads));
      _scrollToBottom();
    }
    unawaited(_runPendingQueuedUploads(roomId, uploads));
  }

  Future<void> _runPendingQueuedUploads(
    String roomId,
    List<_PendingUpload> uploads,
  ) async {
    _setUploading(true);
    try {
      for (final upload in uploads) {
        if (_isPendingUploadCancelled(upload.id) || upload.cancelled) continue;
        if (mounted) setState(() => upload.started = true);

        try {
          await _sendPendingUpload(roomId, upload);
          _removePendingUpload(upload.id);
          await _transferQueue.remove(upload.id);
          _cancelledPendingUploadIds.remove(upload.id);
        } catch (e) {
          if (e is! MatrixUploadCancelledException &&
              !_isPendingUploadCancelled(upload.id) &&
              !upload.cancelled) {
            await _transferQueue.markFailed(upload.id, e);
            _schedulePendingUploadRetry(roomId, upload);
            if (mounted) {
              setState(() {
                upload.failed = true;
                upload.error = e.toString();
              });
            }
            _showSnackBar(
              'Failed to send ${upload.isAudio ? 'audio' : 'file'}: $e',
            );
          } else {
            await _transferQueue.cancel(upload.id);
            _removePendingUpload(upload.id);
            _cancelledPendingUploadIds.remove(upload.id);
          }
        }
      }
    } finally {
      _setUploading(false);
      _scrollToBottom();
    }
  }

  Future<void> _retryPendingUpload(_PendingUpload upload) async {
    final room = _room;
    if (room == null || _isUploadBusy) return;
    _cancelledPendingUploadIds.remove(upload.id);
    upload.cancelled = false;
    upload.failed = false;
    upload.error = null;
    upload.uploadedBytes = 0;
    upload.started = false;
    await _transferQueue.retry(upload.id);
    if (mounted) setState(() {});
    await _runSinglePendingMediaUpload(room.id, upload);
  }

  void _schedulePendingUploadRetry(String roomId, _PendingUpload upload) {
    if (!_transferQueue.shouldAutoRetry(upload.id) || upload.cancelled) return;
    final retryAt = _transferQueue.retryAtFor(upload.id);
    if (retryAt == null) return;
    final delay = retryAt.difference(DateTime.now());
    unawaited(Future<void>.delayed(delay.isNegative ? Duration.zero : delay,
        () async {
      if (!mounted ||
          upload.cancelled ||
          _isPendingUploadCancelled(upload.id)) {
        return;
      }
      if (!_transferQueue.shouldAutoRetry(upload.id)) return;
      try {
        await _transferQueue.retry(upload.id);
        if (!mounted) return;
        setState(() {
          upload.failed = false;
          upload.error = null;
          upload.started = false;
          upload.uploadedBytes = 0;
        });
        await _runSinglePendingMediaUpload(roomId, upload);
      } catch (e) {
        debugPrint('[TransferQueue] Automatic retry failed: $e');
      }
    }));
  }

  Future<void> _pickAndSendAudioWithPending() async {
    final room = _room;
    if (room == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }
    if (!_ensureRoomActionAllowed(XmoRoomPermission.sendMedia) ||
        !_ensureSlowModeAllowed()) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final uploads = <_PendingUpload>[];
    for (final picked in result.files) {
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      final durationMs = await _readAudioDurationMs(picked.path);
      uploads.add(
        _createPendingAudioUpload(
          bytes: bytes,
          fileName: picked.name,
          mimeType: lookupMimeType(picked.name) ?? 'audio/mpeg',
          durationMs: durationMs,
        ),
      );
    }
    if (uploads.isEmpty) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }

    _startPendingQueuedUploads(room.id, uploads);
  }

  Future<int> _readAudioDurationMs(String? path) async {
    if (path == null || path.isEmpty) return 0;
    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(path);
      return duration?.inMilliseconds ?? 0;
    } catch (e) {
      debugPrint('[AudioUpload] Failed to read duration: $e');
      return 0;
    } finally {
      await player.dispose();
    }
  }

  Future<void> _pickAndSendFileWithPending() async {
    final room = _room;
    if (room == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }
    if (!_ensureRoomActionAllowed(XmoRoomPermission.sendMedia) ||
        !_ensureSlowModeAllowed()) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final uploads = <_PendingUpload>[];
    for (final picked in result.files) {
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      uploads.add(
        _createPendingFileUpload(
          bytes: bytes,
          fileName: picked.name,
          mimeType: lookupMimeType(picked.name) ?? 'application/octet-stream',
        ),
      );
    }
    if (uploads.isEmpty) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }

    _startPendingQueuedUploads(room.id, uploads);
  }

  void _showAttachmentSheet() {
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }
    showChatAttachmentSheet(
      context: context,
      onGallery: () {
        _openGalleryPreviewForChat();
      },
      onCamera: () {
        _openCameraForChat();
      },
      onAudio: () {
        _pickAndSendAudioWithPending();
      },
      onDocuments: () {
        _pickAndSendFileWithPending();
      },
      onSticker: () {
        _pickAndSendSticker();
      },
      onPoll: () {
        _showPollComposer();
      },
      onContacts: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contacts sharing coming soon!'),
              backgroundColor: kDarkGrey,
            ),
          );
        }
      },
    );
  }

  Future<void> _pickAndSendSticker() async {
    final room = _room;
    if (room == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }
    if (!_ensureRoomActionAllowed(XmoRoomPermission.sendStickers) ||
        !_ensureSlowModeAllowed()) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
      ],
      withData: true,
      allowMultiple: false,
    );
    final picked =
        result == null || result.files.isEmpty ? null : result.files.first;
    final bytes = picked?.bytes;
    if (picked == null || bytes == null || bytes.isEmpty) return;

    try {
      _setUploading(true);
      await widget.matrixProvider.service.sendSticker(
        roomId: room.id,
        bytes: bytes,
        fileName: picked.name,
        mimeType:
            lookupMimeType(picked.name, headerBytes: bytes) ?? 'image/png',
      );
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to send sticker: $e');
    } finally {
      _setUploading(false);
    }
  }

  Future<void> _showPollComposer() async {
    final room = _room;
    if (room == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }
    if (!_ensureRoomActionAllowed(XmoRoomPermission.sendPolls) ||
        !_ensureSlowModeAllowed()) {
      return;
    }

    final result = await showDialog<_PollComposeResult>(
      context: context,
      builder: (_) => const _PollComposerDialog(),
    );
    if (result == null) return;

    try {
      await widget.matrixProvider.service.sendPoll(
        roomId: room.id,
        question: result.question,
        options: result.options,
      );
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to send poll: $e');
    }
  }

  Future<void> _openCameraForChat() async {
    final room = _room;
    if (room == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }
    if (!_ensureRoomActionAllowed(XmoRoomPermission.sendMedia) ||
        !_ensureSlowModeAllowed()) {
      return;
    }

    final result = await Navigator.push<CameraCaptureResult>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (!mounted || result == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }

    if (result.type == CameraCaptureMediaType.video) {
      await _sendVideoWithPending(
        room.id,
        bytes: result.bytes,
        fileName: result.fileName,
        mimeType: result.mimeType,
        caption: result.caption,
      );
    } else {
      await _sendPhotoWithPending(
        room.id,
        bytes: result.bytes,
        fileName: result.fileName,
        mimeType: result.mimeType,
        caption: result.caption,
      );
    }
    _scrollToBottom();
  }

  Future<void> _openGalleryPreviewForChat() async {
    final room = _room;
    if (room == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }
    if (!_ensureRoomActionAllowed(XmoRoomPermission.sendMedia) ||
        !_ensureSlowModeAllowed()) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'bmp',
        'webp',
        'heic',
        'heif',
        'mp4',
        'mov',
        'avi',
        'mkv',
        'webm',
        'flv',
        'wmv',
        'm4v',
        '3gp',
      ],
      withData: true,
      allowMultiple: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    if (result.files.length > 1) {
      final uploads = <_PendingUpload>[];
      for (final picked in result.files) {
        final bytes = picked.bytes;
        if (bytes == null || bytes.isEmpty) continue;

        final fileName = picked.name;
        final mimeType = lookupMimeType(fileName, headerBytes: bytes) ??
            'application/octet-stream';
        final isImage = mimeType.startsWith('image/');
        final isVideo = mimeType.startsWith('video/');

        if (!isImage && !isVideo) {
          _showSnackBar('Please select only photos or videos');
          return;
        }

        uploads.add(_createPendingMediaUpload(
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          isVideo: isVideo,
        ));
      }

      if (uploads.isNotEmpty) {
        _startPendingAlbumUpload(room.id, uploads);
      }
      return;
    }

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final fileName = picked.name;
    final mimeType = lookupMimeType(fileName, headerBytes: bytes) ??
        'application/octet-stream';
    final isImage = mimeType.startsWith('image/');
    final isVideo = mimeType.startsWith('video/');

    if (!isImage && !isVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select only photos or videos'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final previewResult = await Navigator.push<CameraCaptureResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          type: isVideo
              ? CameraCaptureMediaType.video
              : CameraCaptureMediaType.image,
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
        ),
      ),
    );
    if (!mounted || previewResult == null) return;
    if (_isUploadBusy) {
      _showSnackBar('Please wait for the current upload to finish.');
      return;
    }

    if (previewResult.type == CameraCaptureMediaType.video) {
      await _sendVideoWithPending(
        room.id,
        bytes: previewResult.bytes,
        fileName: previewResult.fileName,
        mimeType: previewResult.mimeType,
        caption: previewResult.caption,
      );
    } else {
      await _sendPhotoWithPending(
        room.id,
        bytes: previewResult.bytes,
        fileName: previewResult.fileName,
        mimeType: previewResult.mimeType,
        caption: previewResult.caption,
      );
    }
    _scrollToBottom();
  }

  // ignore: unused_element
  Future<void> _playVideo(Event event) async {
    if (!_canDownloadAttachment(event)) {
      _showSnackBar('Please wait until the video is ready.');
      return;
    }
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: kLimeGreen,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Loading video…',
                style: GoogleFonts.inter(color: kWhite, fontSize: 13),
              ),
            ],
          ),
          backgroundColor: kDarkerGrey,
          duration: const Duration(seconds: 30),
        ),
      );

      final matrixFile = await _downloadAttachmentWithQueue(
        event,
        activeLabel:
            'Loading ${event.body.isNotEmpty ? event.body : 'video'}...',
        failurePrefix: 'Failed to load video',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FullscreenVideoPlayer(
            videoBytes: matrixFile.bytes,
            mimeType: matrixFile.mimeType,
            title: event.body,
            onReply: () async => _setReplyTo(event),
            onDelete: _canDeleteMessage(event)
                ? () async => _deleteMessage(event)
                : null,
          ),
        ),
      );
    } on MatrixDownloadCancelledException {
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openVideoPlayer(Event event) async {
    if (!_canDownloadAttachment(event)) {
      _showSnackBar('Please wait until the video is ready.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPlayer.loading(
          videoFuture: _downloadAttachmentWithQueue(
            event,
            activeLabel:
                'Loading ${event.body.isNotEmpty ? event.body : 'video'}...',
            failurePrefix: 'Failed to load video',
          ),
          title: event.body,
          onReply: () async => _setReplyTo(event),
          onDelete: _canDeleteMessage(event)
              ? () async => _deleteMessage(event)
              : null,
        ),
      ),
    );
  }

  void _openFullscreenImage(Uint8List bytes, String title, Event event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenImageViewer(
          imageBytes: bytes,
          title: title,
          event: event,
          onReply: () async => _setReplyTo(event),
          onDelete: _canDeleteMessage(event)
              ? () async => _deleteMessage(event)
              : null,
        ),
      ),
    );
  }

  Future<MatrixFile> _downloadAttachmentWithQueue(
    Event event, {
    required String activeLabel,
    required String failurePrefix,
    bool showCompletionSnack = false,
    Future<void> Function(MatrixFile file)? onDownloaded,
  }) async {
    if (!_canDownloadAttachment(event)) {
      _showSnackBar('Please wait until the attachment is ready.');
      throw const MatrixDownloadCancelledException();
    }
    TransferJob? downloadJob;
    final messenger = ScaffoldMessenger.of(context);
    var cancellationSnackShown = false;

    void showDownloadCancelledSnackBar() {
      if (!mounted || cancellationSnackShown) return;
      cancellationSnackShown = true;
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Download cancelled'),
          backgroundColor: kLimeGreen,
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      final fileName = event.body.isNotEmpty ? event.body : 'download';
      final info = event.content['info'];
      final size = info is Map ? (info['size'] as num?)?.toInt() ?? 0 : 0;
      downloadJob = await _transferQueue.createDownloadJob(
        roomId: event.room.id,
        fileName: fileName,
        mimeType: _attachmentMimeTypeFor(event),
        kind: _downloadTransferKindFor(event),
        totalBytes: size,
      );
      final claimed = await _transferQueue.markRunning(downloadJob.id);
      if (!claimed) {
        throw StateError('Download is already running');
      }

      messenger.showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  activeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: kBlack,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _DownloadSnackBarContent(
                jobId: downloadJob.id,
                initialJobs: _transferQueue.jobs,
                stream: _transferQueue.stream,
                onCancel: () {
                  unawaited(_transferQueue.cancel(downloadJob!.id));
                  showDownloadCancelledSnackBar();
                },
              ),
            ],
          ),
          backgroundColor: kWhite,
          padding: EdgeInsets.zero,
          duration: const Duration(minutes: 5),
        ),
      );

      final matrixFile = await event.downloadAndDecryptAttachment(
        downloadCallback: _mediaHandler.authenticatedDownloadWithProgress(
          onProgress: (downloadedBytes, totalBytes) {
            unawaited(_transferQueue.updateProgress(
              downloadJob!.id,
              downloadedBytes,
              totalBytes,
            ));
          },
          isCancelled: () => _transferQueue.isCancelled(downloadJob!.id),
        ),
      );
      if (_transferQueue.isCancelled(downloadJob.id)) {
        throw const MatrixDownloadCancelledException();
      }
      final bytes = matrixFile.bytes;
      await _transferQueue.updateProgress(
        downloadJob.id,
        bytes.length,
        bytes.length,
      );
      if (_transferQueue.isCancelled(downloadJob.id)) {
        throw const MatrixDownloadCancelledException();
      }

      if (bytes.isEmpty) {
        if (mounted) {
          messenger.removeCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text('$failurePrefix: downloaded file is empty'),
              backgroundColor: Colors.red,
            ),
          );
        }
        throw Exception('Downloaded file is empty');
      }
      if (_transferQueue.isCancelled(downloadJob.id)) {
        throw const MatrixDownloadCancelledException();
      }
      if (onDownloaded != null) {
        await onDownloaded(matrixFile);
      }
      if (_transferQueue.isCancelled(downloadJob.id)) {
        throw const MatrixDownloadCancelledException();
      }

      await _transferQueue.markCompleted(downloadJob.id);
      await _transferQueue.remove(downloadJob.id);
      if (mounted) {
        messenger.removeCurrentSnackBar();
        if (showCompletionSnack) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(kIsWeb
                  ? 'Downloaded: ${matrixFile.name}'
                  : 'Downloaded successfully'),
              backgroundColor: kLimeGreen,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      return matrixFile;
    } catch (e) {
      if (e is MatrixDownloadCancelledException ||
          (downloadJob != null && _transferQueue.isCancelled(downloadJob.id))) {
        if (downloadJob != null) {
          await _transferQueue.cancel(downloadJob.id);
        }
        showDownloadCancelledSnackBar();
        throw const MatrixDownloadCancelledException();
      }
      if (downloadJob != null) {
        await _transferQueue.markFailed(downloadJob.id, e);
      }
      if (mounted) {
        messenger.removeCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('$failurePrefix: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _downloadAndOpenFile(Event event) async {
    if (!_canDownloadAttachment(event)) {
      _showSnackBar('Please wait until the attachment is ready.');
      return;
    }
    try {
      await _downloadAttachmentWithQueue(
        event,
        activeLabel:
            'Downloading ${event.body.isNotEmpty ? event.body : 'file'}...',
        failurePrefix: 'Failed to download',
        showCompletionSnack: true,
        onDownloaded: (file) => web_download.downloadFile(
          file.bytes,
          file.name,
          mimeType: file.mimeType,
          storageCategory: _downloadStorageCategoryFor(event),
        ),
      );
    } on MatrixDownloadCancelledException {
      return;
    } catch (_) {
      return;
    }
  }

  String _attachmentMimeTypeFor(Event event) {
    final info = event.content['info'];
    final mimetype = info is Map ? info['mimetype'] : null;
    if (mimetype is String && mimetype.isNotEmpty) return mimetype;
    return lookupMimeType(event.body) ?? 'application/octet-stream';
  }

  TransferKind _downloadTransferKindFor(Event event) {
    switch (event.messageType) {
      case MessageTypes.Image:
        return TransferKind.photo;
      case MessageTypes.Video:
        return TransferKind.video;
      case MessageTypes.Audio:
        return TransferKind.audio;
      default:
        return TransferKind.file;
    }
  }

  Future<void> _openMessageAttachment(Event event) async {
    if (!_canDownloadAttachment(event)) {
      _showSnackBar('Please wait until the attachment is ready.');
      return;
    }
    try {
      final displayEvent = _displayEventFor(event);
      await _downloadAttachmentWithQueue(
        displayEvent,
        activeLabel:
            'Opening ${displayEvent.body.isNotEmpty ? displayEvent.body : 'file'}...',
        failurePrefix: 'Could not open file',
        onDownloaded: (file) async {
          if (kIsWeb) {
            await web_download.downloadFile(
              file.bytes,
              file.name,
              mimeType: file.mimeType,
              storageCategory: _downloadStorageCategoryFor(displayEvent),
            );
          } else {
            await native_share.openFile(
              file.bytes,
              file.name,
              mimeType: file.mimeType,
            );
          }
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } on MatrixDownloadCancelledException {
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<MatrixFile> _downloadAttachment(Event event) async {
    if (!_canDownloadAttachment(event)) {
      _showSnackBar('Please wait until the attachment is ready.');
      throw const MatrixDownloadCancelledException();
    }
    return event.downloadAndDecryptAttachment(
      downloadCallback: _mediaHandler.authenticatedDownload(),
    );
  }

  String _downloadStorageCategoryFor(Event event) {
    switch (event.messageType) {
      case MessageTypes.Video:
        return 'videos';
      case MessageTypes.Audio:
        return 'audio';
      case MessageTypes.Image:
        return 'photos';
      case MessageTypes.File:
      default:
        return 'files';
    }
  }

  bool _isEditReplacementEvent(Event event) {
    return event.relationshipType == RelationshipTypes.edit &&
        event.relationshipEventId != null &&
        event.content['m.new_content'] is Map;
  }

  Event _displayEventFor(Event event) {
    final timeline = _timeline;
    return timeline == null ? event : event.getDisplayEvent(timeline);
  }

  List<Event> _visibleMessages() {
    return _timeline?.events
            .where((e) =>
                !e.redacted &&
                !_isEditReplacementEvent(e) &&
                !_isPendingAlbumTimelineEvent(e) &&
                !MatrixService.isGroupCallPushMarker(e) &&
                (e.type == EventTypes.Message ||
                    e.type == EventTypes.Encrypted ||
                    e.type == EventTypes.Sticker ||
                    e.type == _pollStartEventType))
            .toList()
            .reversed
            .toList() ??
        [];
  }

  bool _isPendingAlbumTimelineEvent(Event event) {
    if (_pendingAlbumUploads.isEmpty || event.senderId != _myUserId) {
      return false;
    }

    for (final album in _pendingAlbumUploads) {
      final earliestVisibleTime =
          album.createdAt.subtract(const Duration(seconds: 5));
      if (event.originServerTs.isBefore(earliestVisibleTime)) continue;

      for (final upload in album.uploads) {
        if (_matchesPendingAlbumUpload(event, upload)) return true;
      }
    }

    return false;
  }

  bool _matchesPendingAlbumUpload(Event event, _PendingUpload upload) {
    final displayEvent = _displayEventFor(event);
    final expectedType =
        upload.isVideo ? MessageTypes.Video : MessageTypes.Image;
    if (displayEvent.messageType != expectedType) return false;

    final fileName = displayEvent.content['filename'];
    final body = displayEvent.body;
    final sameName = fileName == upload.fileName || body == upload.fileName;
    if (!sameName) return false;

    final info = displayEvent.content['info'];
    if (info is Map) {
      final size = info['size'];
      if (size is num && size.toInt() != upload.bytes.length) return false;
    }

    return true;
  }

  bool _hasEditReplacement(Event event) {
    final timeline = _timeline;
    if (timeline == null) return false;
    return event
        .aggregatedEvents(timeline, RelationshipTypes.edit)
        .any((edit) => edit.senderId == event.senderId);
  }

  Future<void> _scrollToAndHighlightMessage(String eventId) async {
    final key = _messageKeys[eventId];
    final context = key?.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.38,
      );
      _highlightMessage(eventId);
      return;
    }

    final messages = _visibleMessages();
    final index = messages.indexWhere((event) => event.eventId == eventId);
    if (index == -1 || !_scrollCtrl.hasClients) {
      _showSnackBar('Original message not found');
      return;
    }

    final estimatedOffset = (index * 92.0).clamp(
      _scrollCtrl.position.minScrollExtent,
      _scrollCtrl.position.maxScrollExtent,
    );
    await _scrollCtrl.animateTo(
      estimatedOffset,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );

    if (!mounted) return;
    _highlightMessage(eventId);
  }

  Future<void> _openInitialHighlightedMessage() async {
    final eventId = widget.initialHighlightedEventId?.trim();
    if (_handledInitialHighlightedEvent || eventId == null || eventId.isEmpty) {
      return;
    }
    _handledInitialHighlightedEvent = true;

    var found = _visibleMessages().any((event) => event.eventId == eventId);
    while (!found &&
        mounted &&
        !_historyExhausted &&
        _timeline?.canRequestHistory == true) {
      final beforeCount = _timeline!.events.length;
      await _loadOlderMessages(
        historyCount: 100,
        preserveScroll: false,
      );
      found = _visibleMessages().any((event) => event.eventId == eventId);
      if (_timeline!.events.length <= beforeCount) break;
    }

    if (!mounted) return;
    if (!found) {
      _showSnackBar('Original message not found');
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_scrollToAndHighlightMessage(eventId));
      }
    });
  }

  Future<void> _openPrivateReplySource(
    String sourceRoomId,
    String sourceEventId,
  ) async {
    final roomId = sourceRoomId.trim();
    final eventId = sourceEventId.trim();
    if (roomId.isEmpty || eventId.isEmpty) return;

    if (roomId == _room?.id) {
      await _scrollToAndHighlightMessage(eventId);
      return;
    }

    final sourceRoom = await _getRoomByIdAfterSync(roomId);
    if (!mounted) return;
    if (sourceRoom == null || sourceRoom.membership != Membership.join) {
      _showSnackBar('Original group is unavailable');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatrixChatScreen(
          room: sourceRoom,
          matrixProvider: widget.matrixProvider,
          initialHighlightedEventId: eventId,
        ),
      ),
    );
  }

  void _highlightMessage(String eventId) {
    _highlightTimer?.cancel();
    if (mounted) {
      setState(() => _highlightedEventId = eventId);
    }
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _highlightedEventId == eventId) {
        setState(() => _highlightedEventId = null);
      }
    });
  }

  List<_MessageListItem> _buildMessageListItems(List<Event> messages) {
    final items = <_MessageListItem>[];
    var index = 0;

    while (index < messages.length) {
      final event = messages[index];
      if (!_canGroupInMediaAlbum(event)) {
        items.add(_MessageListItem.message(event));
        index++;
        continue;
      }

      final group = <Event>[event];
      var cursor = index + 1;
      while (cursor < messages.length &&
          _canAppendToMediaAlbum(group.last, messages[cursor])) {
        group.add(messages[cursor]);
        cursor++;
      }

      if (group.length == 1) {
        items.add(_MessageListItem.message(group.first));
      } else {
        for (var start = 0; start < group.length; start += 10) {
          final end = start + 10 > group.length ? group.length : start + 10;
          final chunk = group.sublist(start, end);
          if (chunk.length == 1) {
            items.add(_MessageListItem.message(chunk.first));
          } else {
            items.add(_MessageListItem.album(chunk));
          }
        }
      }

      index = cursor;
    }

    return items;
  }

  Key _messageListItemKey(_MessageListItem item) {
    final albumEvents = item.albumEvents;
    if (albumEvents != null) {
      return ValueKey(
        'album_${albumEvents.map((event) => event.eventId).join('_')}',
      );
    }
    return ValueKey('message_${item.event?.eventId}');
  }

  bool _canAppendToMediaAlbum(Event previous, Event next) {
    if (!_canGroupInMediaAlbum(next)) return false;
    if (previous.senderId != next.senderId) return false;

    final gap = next.originServerTs.difference(previous.originServerTs).abs();
    return gap <= const Duration(minutes: 2);
  }

  bool _canGroupInMediaAlbum(Event event) {
    final displayEvent = _displayEventFor(event);
    final msgtype = displayEvent.messageType;
    final isMedia =
        msgtype == MessageTypes.Image || msgtype == MessageTypes.Video;
    if (!isMedia) return false;
    if (_hasEditReplacement(event)) return false;

    final caption = displayEvent.content['xmo_caption'];
    return caption is! String || caption.trim().isEmpty;
  }

  Widget _buildBubble(Event event) {
    final key = _messageKeys.putIfAbsent(event.eventId, GlobalKey.new);
    final displayEvent = _displayEventFor(event);
    final isEdited = _hasEditReplacement(event);
    final isMe = event.senderId == _myUserId;
    final time = _formatTime(event.originServerTs);
    final senderName = MatrixService.cleanName(event.senderId);

    final msgtype = displayEvent.messageType;
    final isImage = msgtype == MessageTypes.Image;
    final isVideo = msgtype == MessageTypes.Video;
    final isAudio = msgtype == MessageTypes.Audio;
    final isFile = msgtype == MessageTypes.File;

    // Determine if user can perform any actions on this message
    final canEdit = _canEditMessage(event);
    final canDelete = _canDeleteMessage(event);
    final canReply = _canReplyToMessage(event);
    final canForward = _canForwardMessage(event);
    final canCopy = _copyableMessageText(event) != null;
    final canDownload = _canDownloadAttachment(event);
    final isPinned = _pinnedEvents.any((e) => e.eventId == event.eventId);
    final canPin = _canPinMessage(event);
    final canDeleteOwnAttachment = isMe && canDelete;
    final canReact = _canReactToMessage(event);
    final canShowMenu = canReply ||
        canCopy ||
        canForward ||
        canDownload ||
        canEdit ||
        canDelete ||
        canPin ||
        canReact;

    return KeyedSubtree(
      key: key,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        color: _highlightedEventId == event.eventId
            ? kLimeGreen.withValues(alpha: 0.22)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GestureDetector(
            onLongPress: canShowMenu ? () => _showMessageOptions(event) : null,
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: 4,
                  left: isMe ? 60 : 0,
                  right: isMe ? 0 : 60,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (displayEvent.type == EventTypes.Sticker)
                      _buildStickerBubble(
                        event: displayEvent,
                        isMe: isMe,
                        senderName: senderName,
                        time: time,
                      )
                    else if (displayEvent.type == _pollStartEventType)
                      _buildPollBubble(
                        event: displayEvent,
                        isMe: isMe,
                        senderName: senderName,
                        time: time,
                      )
                    else if (isImage || isVideo)
                      MediaMessageBubble(
                        event: displayEvent,
                        isMe: isMe,
                        senderName: senderName,
                        time: time,
                        isImage: isImage,
                        loadImageBytes: _mediaHandler.loadImageBytes,
                        loadVideoThumbnail: _mediaHandler.loadVideoThumbnail,
                        playVideo: _openVideoPlayer,
                        downloadAttachment: _downloadAndOpenFile,
                        shareAttachment: _shareMessageAttachment,
                        onReply: canReply ? () => _setReplyTo(event) : null,
                        onForward:
                            canForward ? () => _forwardMessage(event) : null,
                        onPin: canPin ? () => _togglePinMessage(event) : null,
                        onDelete: canDeleteOwnAttachment
                            ? () => _deleteMessage(event)
                            : null,
                        isPinned: isPinned,
                        openFullscreenImage: _openFullscreenImage,
                        buildMessageStatus: (_) => _buildMessageStatus(event),
                        isEdited: isEdited,
                      )
                    else if (_hasLinkPreview(displayEvent))
                      _buildLinkPreviewBubble(
                        event: displayEvent,
                        isMe: isMe,
                        senderName: senderName,
                        time: time,
                        status: _buildMessageStatus(event),
                      )
                    else
                      TextOrFileMessageBubble(
                        event: displayEvent,
                        isMe: isMe,
                        senderName: senderName,
                        time: time,
                        isAudio: isAudio,
                        isFile: isFile,
                        downloadAndOpenFile: _downloadAndOpenFile,
                        shareAttachment: _shareMessageAttachment,
                        openAttachmentExternally: _openMessageAttachment,
                        downloadAttachment: _downloadAttachment,
                        onReply: canReply ? () => _setReplyTo(event) : null,
                        onForward:
                            canForward ? () => _forwardMessage(event) : null,
                        onPin: canPin ? () => _togglePinMessage(event) : null,
                        onDelete: canDeleteOwnAttachment
                            ? () => _deleteMessage(event)
                            : null,
                        isPinned: isPinned,
                        buildMessageStatus: (_) => _buildMessageStatus(event),
                        loadImageBytes: _mediaHandler.loadImageBytes,
                        loadVideoThumbnail: _mediaHandler.loadVideoThumbnail,
                        isEdited: isEdited,
                        onReplyTap: _scrollToAndHighlightMessage,
                        onPrivateReplyTap: _openPrivateReplySource,
                        mentionMembers: _mentionMembersForCurrentRoom(),
                        onMentionTap: _showMentionProfileSheet,
                      ),
                    MessageReactions(
                      reactions: _reactionSummariesFor(event),
                      isMyMessage: isMe,
                      onTap: (reaction) {
                        if (_canReactToMessage(event)) {
                          _showReactionDetails(event, reaction);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _hasLinkPreview(Event event) {
    return event.type == EventTypes.Message &&
        event.content['com.xmo.link_preview'] is Map;
  }

  Widget _buildStickerBubble({
    required Event event,
    required bool isMe,
    required String senderName,
    required String time,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1A2A1A) : const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                senderName,
                style: GoogleFonts.inter(
                  color: kLimeGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 190,
              height: 190,
              child: FutureBuilder<Uint8List?>(
                future: _mediaHandler.loadImageBytes(event),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null || bytes.isEmpty) {
                    return const ColoredBox(
                      color: kDarkGrey,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: kLimeGreen,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: kDarkGrey,
                      child: Icon(Icons.sticky_note_2, color: kLightGrey),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: GoogleFonts.inter(
              color: isMe ? kLimeGreen : kLightGrey,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPollBubble({
    required Event event,
    required bool isMe,
    required String senderName,
    required String time,
  }) {
    final question = _pollQuestion(event);
    final answers = _pollAnswers(event);
    final votes = _pollVoteCounts(event.eventId);
    final totalVotes = votes.values.fold<int>(0, (sum, count) => sum + count);
    final ownVote = _ownPollVote(event.eventId);

    return Container(
      width: _responsiveBubbleWidth(
        context,
        compact: 285,
        regular: 320,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1A2A1A) : const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                senderName,
                style: GoogleFonts.inter(
                  color: kLimeGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            children: [
              const Icon(Icons.poll_rounded, color: kLimeGreen, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final answer in answers) ...[
            _PollOptionTile(
              text: answer.text,
              count: votes[answer.id] ?? 0,
              total: totalVotes,
              selected: ownVote == answer.id,
              onTap: _canSendMessages && _isStableMessageActionTarget(event)
                  ? () => _voteInPoll(event, answer.id)
                  : null,
            ),
            const SizedBox(height: 7),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                  color: kLightGrey,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                time,
                style: GoogleFonts.inter(
                  color: isMe ? kLimeGreen : kLightGrey,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLinkPreviewBubble({
    required Event event,
    required bool isMe,
    required String senderName,
    required String time,
    required Widget status,
  }) {
    final preview = event.content['com.xmo.link_preview'];
    if (preview is! Map) return const SizedBox.shrink();
    final rawUrl = preview['url']?.toString().trim();
    if (rawUrl == null || rawUrl.isEmpty) return const SizedBox.shrink();
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return const SizedBox.shrink();

    final title = preview['title']?.toString().trim();
    final host = preview['host']?.toString().trim();
    final description = preview['description']?.toString().trim();
    final siteName = preview['site_name']?.toString().trim();
    final imageUrl = preview['image_url']?.toString().trim();
    final label = (title == null || title.isEmpty) ? host ?? uri.host : title;
    final body = event.body.trim();

    return Container(
      width: _responsiveBubbleWidth(
        context,
        compact: 270,
        regular: 315,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1A2A1A) : const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openExternalUrl(uri),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  senderName,
                  style: GoogleFonts.inter(
                    color: kLimeGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF203520) : const Color(0xFF252527),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(9),
                        bottomRight: Radius.circular(9),
                      ),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                            if (_isVideoPreviewHost(uri.host))
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: kWhite,
                                    size: 32,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            color: kWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            description,
                            style: GoogleFonts.inter(
                              color: kLightGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.link_rounded,
                              color: kLightGrey,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                (siteName == null || siteName.isEmpty)
                                    ? host ?? uri.host
                                    : siteName,
                                style: GoogleFonts.inter(
                                  color: kLightGrey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (body.isNotEmpty) ...[
                  Expanded(
                    child: Text(
                      body,
                      style: GoogleFonts.inter(
                        color: kAudioBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.18,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else
                  const Spacer(),
                Text(
                  time,
                  style: GoogleFonts.inter(
                    color: isMe ? kLimeGreen : kLightGrey,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  status,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isVideoPreviewHost(String host) {
    final lower = host.toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('vimeo.com');
  }

  Future<void> _openExternalUrl(Uri uri) async {
    final launchUri =
        uri.hasScheme ? uri : Uri.parse('https://${uri.toString()}');
    if (!await launchUrl(launchUri, mode: LaunchMode.externalApplication)) {
      _showSnackBar('Unable to open link');
    }
  }

  List<MessageReactionSummary> _reactionSummariesFor(Event event) {
    final usersByEmoji = <String, List<ReactionUser>>{};
    final reactedByMe = <String>{};
    final events = _timeline?.events ?? const <Event>[];
    for (final reaction in events) {
      if (reaction.redacted || reaction.type != EventTypes.Reaction) continue;
      if (_relationEventId(reaction) != event.eventId) continue;
      final key = _relationKey(reaction);
      if (key == null || key.isEmpty) continue;
      usersByEmoji.putIfAbsent(key, () => <ReactionUser>[]).add(
            _reactionUserFor(reaction.senderId),
          );
      if (reaction.senderId == _myUserId) reactedByMe.add(key);
    }

    final summaries = usersByEmoji.entries.map((entry) {
      return MessageReactionSummary(
        emoji: entry.key,
        count: entry.value.length,
        reactedByMe: reactedByMe.contains(entry.key),
        users: entry.value,
      );
    }).toList(growable: false);

    final quickOrder = {
      for (var i = 0; i < ReactionPicker.quickReactions.length; i++)
        ReactionPicker.quickReactions[i]: i,
    };
    return summaries.toList()
      ..sort((a, b) {
        final byMine = (b.reactedByMe ? 1 : 0) - (a.reactedByMe ? 1 : 0);
        if (byMine != 0) return byMine;
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return (quickOrder[a.emoji] ?? 999).compareTo(
          quickOrder[b.emoji] ?? 999,
        );
      });
  }

  Future<void> _toggleReaction(Event event, String emoji) async {
    final room = _room;
    if (room == null) return;
    if (!_ensureStableMessageActionTarget(event)) return;

    final events = _timeline?.events ?? const <Event>[];
    final myReactions = <Event>[];
    var alreadyReactedWithEmoji = false;
    for (final reaction in events) {
      if (reaction.redacted || reaction.type != EventTypes.Reaction) continue;
      if (reaction.senderId != _myUserId) continue;
      if (_relationEventId(reaction) != event.eventId) continue;
      myReactions.add(reaction);
      if (_relationKey(reaction) == emoji) {
        alreadyReactedWithEmoji = true;
      }
    }

    if (alreadyReactedWithEmoji) {
      for (final reaction in myReactions) {
        if (_relationKey(reaction) != emoji) continue;
        await room.redactEvent(reaction.eventId);
      }
      return;
    }

    for (final reaction in myReactions) {
      await room.redactEvent(reaction.eventId);
    }

    await room.sendReaction(event.eventId, emoji);
  }

  ReactionUser _reactionUserFor(String userId) {
    final room = _room;
    if (room != null) {
      for (final user in room.getParticipants()) {
        if (user.id != userId) continue;
        final displayName = user.displayName?.trim();
        return ReactionUser(
          userId: userId,
          displayName: displayName == null || displayName.isEmpty
              ? _shortUserId(userId)
              : displayName,
          avatarUrl: user.avatarUrl?.toString(),
        );
      }
    }
    return ReactionUser(userId: userId, displayName: _shortUserId(userId));
  }

  String _shortUserId(String userId) {
    final localpart = userId.startsWith('@') ? userId.substring(1) : userId;
    final colon = localpart.indexOf(':');
    return colon == -1 ? localpart : localpart.substring(0, colon);
  }

  String? _myReactionFor(Event event) {
    final events = _timeline?.events ?? const <Event>[];
    for (final reaction in events) {
      if (reaction.redacted || reaction.type != EventTypes.Reaction) continue;
      if (reaction.senderId != _myUserId) continue;
      if (_relationEventId(reaction) != event.eventId) continue;
      final key = _relationKey(reaction);
      if (key != null && key.isNotEmpty) return key;
    }
    return null;
  }

  String? _relationEventId(Event event) {
    final relatesTo = event.content['m.relates_to'];
    if (relatesTo is Map) return relatesTo['event_id']?.toString();
    return event.relationshipEventId;
  }

  String? _relationKey(Event event) {
    final relatesTo = event.content['m.relates_to'];
    if (relatesTo is Map) return relatesTo['key']?.toString();
    return null;
  }

  Map? _pollStartContent(Event event) {
    final stable = event.content[_pollStartContentKey];
    if (stable is Map) return stable;
    final unstable = event.content[_unstablePollStartContentKey];
    if (unstable is Map) return unstable;
    return null;
  }

  String _pollQuestion(Event event) {
    final content = _pollStartContent(event);
    final question = content?['question'];
    if (question is Map) {
      final text = question['m.text'] ?? question['org.matrix.msc1767.text'];
      if (text is String && text.trim().isNotEmpty) return text.trim();
    }
    final body = event.body.trim();
    return body.isEmpty ? 'Poll' : body;
  }

  List<_PollAnswer> _pollAnswers(Event event) {
    final content = _pollStartContent(event);
    final answers = content?['answers'];
    if (answers is! List) return const [];

    final parsed = <_PollAnswer>[];
    for (final answer in answers) {
      if (answer is! Map) continue;
      final id = answer['id']?.toString();
      final text = answer['m.text'] ?? answer['org.matrix.msc1767.text'];
      if (id == null || id.isEmpty || text is! String || text.trim().isEmpty) {
        continue;
      }
      parsed.add(_PollAnswer(id: id, text: text.trim()));
    }
    return parsed;
  }

  Map<String, int> _pollVoteCounts(String pollEventId) {
    final latestVoteBySender = <String, String>{};
    final events = _timeline?.events ?? const <Event>[];
    for (final event in events) {
      if (event.redacted || event.type != _pollResponseEventType) continue;
      if (_relationEventId(event) != pollEventId) continue;
      final answerId = _pollResponseAnswerId(event);
      if (answerId == null || answerId.isEmpty) continue;
      latestVoteBySender[event.senderId] = answerId;
    }
    final optimisticVote = _optimisticPollVotes[pollEventId];
    if (_myUserId.isNotEmpty &&
        optimisticVote != null &&
        optimisticVote.isNotEmpty) {
      latestVoteBySender[_myUserId] = optimisticVote;
    }

    final counts = <String, int>{};
    for (final answerId in latestVoteBySender.values) {
      counts[answerId] = (counts[answerId] ?? 0) + 1;
    }
    return counts;
  }

  String? _ownPollVote(String pollEventId) {
    final optimisticVote = _optimisticPollVotes[pollEventId];
    if (optimisticVote != null && optimisticVote.isNotEmpty) {
      return optimisticVote;
    }
    final events = _timeline?.events ?? const <Event>[];
    for (final event in events) {
      if (event.redacted ||
          event.type != _pollResponseEventType ||
          event.senderId != _myUserId ||
          _relationEventId(event) != pollEventId) {
        continue;
      }
      final answerId = _pollResponseAnswerId(event);
      if (answerId != null && answerId.isNotEmpty) return answerId;
    }
    return null;
  }

  String? _pollResponseAnswerId(Event event) {
    final stable = event.content[_pollResponseContentKey];
    final response =
        stable is Map ? stable : event.content[_unstablePollResponseContentKey];
    if (response is! Map) return null;
    final answers = response['answers'];
    if (answers is List && answers.isNotEmpty) {
      return answers.first?.toString();
    }
    return null;
  }

  Future<void> _voteInPoll(Event pollEvent, String answerId) async {
    final room = _room;
    if (room == null) return;
    if (!_ensureStableMessageActionTarget(pollEvent)) return;
    final pollEventId = pollEvent.eventId;
    final previousVote = _ownPollVote(pollEventId);
    if (previousVote == answerId) return;

    setState(() => _optimisticPollVotes[pollEventId] = answerId);
    try {
      await widget.matrixProvider.service.sendPollResponse(
        roomId: room.id,
        pollEventId: pollEventId,
        answerId: answerId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previousVote == null || previousVote.isEmpty) {
          _optimisticPollVotes.remove(pollEventId);
        } else {
          _optimisticPollVotes[pollEventId] = previousVote;
        }
      });
      _showSnackBar('Failed to vote: $e');
    }
  }

  Widget _buildMediaAlbumBubble(List<Event> events) {
    final primaryEvent = events.last;
    final key = _messageKeys.putIfAbsent(
      'album_${events.map((event) => event.eventId).join('_')}',
      GlobalKey.new,
    );
    final isMe = primaryEvent.senderId == _myUserId;
    final senderName = MatrixService.cleanName(primaryEvent.senderId);
    final time = _formatTime(primaryEvent.originServerTs);
    final canShowMenu = _canReplyToMessage(primaryEvent) ||
        _copyableMessageText(primaryEvent) != null ||
        _canForwardMessage(primaryEvent) ||
        _canDownloadAttachment(primaryEvent) ||
        _canEditMessage(primaryEvent) ||
        _canDeleteMessage(primaryEvent) ||
        _canPinMessage(primaryEvent);

    return KeyedSubtree(
      key: key,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        color: events.any((event) => _highlightedEventId == event.eventId)
            ? kLimeGreen.withValues(alpha: 0.22)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GestureDetector(
            onLongPress:
                canShowMenu ? () => _showMessageOptions(primaryEvent) : null,
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: 4,
                  left: isMe ? 60 : 0,
                  right: isMe ? 0 : 60,
                ),
                child: Column(
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 4),
                        child: Text(
                          senderName,
                          style: GoogleFonts.inter(
                            color: kLimeGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Stack(
                      children: [
                        _buildMediaAlbumGrid(events),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  time,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  _buildMessageStatus(primaryEvent),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    MessageReactions(
                      reactions: _reactionSummariesFor(primaryEvent),
                      isMyMessage: isMe,
                      onTap: (reaction) {
                        if (_canReactToMessage(primaryEvent)) {
                          _showReactionDetails(primaryEvent, reaction);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaAlbumGrid(List<Event> events) {
    final widthLimit = MediaQuery.sizeOf(context).width - 84;
    final albumWidth = widthLimit < 340.0 ? widthLimit : 340.0;
    if (events.length == 3 || events.length == 4) {
      return _buildSplitMediaAlbumGrid(events, albumWidth);
    }

    final rows = _albumRowsForCount(events.length);
    final rowWidgets = <Widget>[];
    var index = 0;

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final rowSize = rows[rowIndex];
      rowWidgets.add(
        _buildAlbumRow(
          events.sublist(index, index + rowSize),
          albumEvents: events,
          height: _albumRowHeight(events.length, rowIndex, albumWidth),
        ),
      );
      if (rowIndex != rows.length - 1) {
        rowWidgets.add(_albumSeparator(height: 1.5));
      }
      index += rowSize;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: albumWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rowWidgets,
        ),
      ),
    );
  }

  Widget _buildSplitMediaAlbumGrid(List<Event> events, double albumWidth) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: albumWidth,
        height: albumWidth * 0.95,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: _buildAlbumTile(events.first, events),
            ),
            _albumSeparator(width: 1.5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 1; i < events.length; i++) ...[
                    Expanded(child: _buildAlbumTile(events[i], events)),
                    if (i != events.length - 1) _albumSeparator(height: 1.5),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<int> _albumRowsForCount(int count) {
    switch (count) {
      case 1:
        return const [1];
      case 2:
        return const [2];
      case 3:
        return const [1, 2];
      case 4:
        return const [2, 2];
      case 5:
        return const [2, 3];
      case 6:
        return const [3, 3];
      case 7:
        return const [2, 3, 2];
      case 8:
        return const [3, 3, 2];
      case 9:
        return const [3, 3, 3];
      default:
        return const [3, 4, 3];
    }
  }

  double _albumRowHeight(int count, int rowIndex, double width) {
    if (count == 1) return width * 0.72;
    if (count == 2) return width * 0.72;
    if (count == 3 && rowIndex == 0) return width * 0.68;
    if (count <= 5 && rowIndex == 0) return width * 0.58;
    return width * 0.38;
  }

  Widget _buildAlbumRow(
    List<Event> rowEvents, {
    required List<Event> albumEvents,
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rowEvents.length; i++) ...[
            Expanded(child: _buildAlbumTile(rowEvents[i], albumEvents)),
            if (i != rowEvents.length - 1) _albumSeparator(width: 1.5),
          ],
        ],
      ),
    );
  }

  Widget _albumSeparator({double? width, double? height}) {
    return SizedBox(
      width: width,
      height: height,
      child: const ColoredBox(color: Color(0xFF2C2C2E)),
    );
  }

  Widget _buildAlbumTile(Event event, List<Event> albumEvents) {
    final displayEvent = _displayEventFor(event);
    final isVideo = displayEvent.messageType == MessageTypes.Video;
    final canShowMenu = _canReplyToMessage(event) ||
        _copyableMessageText(event) != null ||
        _canForwardMessage(event) ||
        _canDeleteMessage(event) ||
        _canDownloadAttachment(event);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openAlbumMediaViewer(albumEvents, event),
      onLongPress: canShowMenu ? () => _showMessageOptions(event) : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          isVideo
              ? _buildAlbumVideoThumbnail(displayEvent)
              : _buildAlbumImageThumbnail(displayEvent),
          if (isVideo)
            Center(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumImageThumbnail(Event event) {
    final cachedBytes = MediaHandler.getCachedImageBytes(
      event.eventId,
      getThumbnail: true,
    );
    return FutureBuilder<Uint8List?>(
      initialData: cachedBytes,
      future: cachedBytes == null
          ? _mediaHandler.loadImageBytes(event, getThumbnail: true)
          : null,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: kDarkGrey,
            child: const Center(
              child: CircularProgressIndicator(
                color: kLimeGreen,
                strokeWidth: 2,
              ),
            ),
          );
        }

        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: kDarkGrey,
            child: Icon(Icons.broken_image_outlined, color: kLightGrey),
          ),
        );
      },
    );
  }

  Widget _buildAlbumVideoThumbnail(Event event) {
    final cachedBytes = MediaHandler.getCachedThumbnail(event.eventId);
    return FutureBuilder<Uint8List?>(
      initialData: cachedBytes,
      future:
          cachedBytes == null ? _mediaHandler.loadVideoThumbnail(event) : null,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Icon(Icons.videocam, color: kLightGrey, size: 28),
            ),
          );
        }

        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Colors.black,
            child: Icon(Icons.videocam, color: kLightGrey, size: 28),
          ),
        );
      },
    );
  }

  void _openAlbumMediaViewer(List<Event> events, Event initialEvent) {
    var initialIndex = events.indexWhere(
      (event) => event.eventId == initialEvent.eventId,
    );
    if (initialIndex < 0) {
      initialIndex = 0;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumMediaViewer(
          events: events,
          initialIndex: initialIndex,
          loadImageBytes: _mediaHandler.loadImageBytes,
          loadVideoThumbnail: _mediaHandler.loadVideoThumbnail,
          downloadAttachment: _downloadAttachment,
          playVideo: _openVideoPlayer,
          onReply: (event) async {
            if (_canReplyToMessage(event)) _setReplyTo(event);
          },
          onDelete: (event) async {
            if (_canDeleteMessage(event)) await _deleteMessage(event);
          },
          canDelete: _canDeleteMessage,
        ),
      ),
    );
  }

  List<GroupMember> _mentionMembersForCurrentRoom() {
    final room = _room;
    if (room == null) return const [];
    if (_groupMembers.isNotEmpty) return _groupMembers;

    return room
        .getParticipants()
        .where((user) => user.id != _myUserId)
        .map((user) => GroupMember.fromUser(user, room))
        .toList(growable: false);
  }

  Widget _buildPendingAlbumUploadBubble(_PendingAlbumUpload album) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(left: 60),
          child: Stack(
            children: [
              _buildPendingAlbumGrid(
                album.uploads,
                currentUploadId: album.currentUploadId,
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _pendingClock(album.createdAt),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.access_time_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingAlbumGrid(
    List<_PendingUpload> uploads, {
    required String? currentUploadId,
  }) {
    final widthLimit = MediaQuery.sizeOf(context).width - 84;
    final albumWidth = widthLimit < 340.0 ? widthLimit : 340.0;
    if (uploads.length == 3 || uploads.length == 4) {
      return _buildSplitPendingAlbumGrid(
        uploads,
        albumWidth,
        currentUploadId: currentUploadId,
      );
    }

    final rows = _albumRowsForCount(uploads.length);
    final rowWidgets = <Widget>[];
    var index = 0;

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final rowSize = rows[rowIndex];
      rowWidgets.add(
        _buildPendingAlbumRow(
          uploads.sublist(index, index + rowSize),
          height: _albumRowHeight(uploads.length, rowIndex, albumWidth),
          currentUploadId: currentUploadId,
        ),
      );
      if (rowIndex != rows.length - 1) {
        rowWidgets.add(_albumSeparator(height: 1.5));
      }
      index += rowSize;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: albumWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rowWidgets,
        ),
      ),
    );
  }

  Widget _buildSplitPendingAlbumGrid(
    List<_PendingUpload> uploads,
    double albumWidth, {
    required String? currentUploadId,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: albumWidth,
        height: albumWidth * 0.95,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: _buildPendingAlbumTile(
                uploads.first,
                isCurrentUpload: uploads.first.id == currentUploadId,
              ),
            ),
            _albumSeparator(width: 1.5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 1; i < uploads.length; i++) ...[
                    Expanded(
                      child: _buildPendingAlbumTile(
                        uploads[i],
                        isCurrentUpload: uploads[i].id == currentUploadId,
                      ),
                    ),
                    if (i != uploads.length - 1) _albumSeparator(height: 1.5),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingAlbumRow(
    List<_PendingUpload> rowUploads, {
    required double height,
    required String? currentUploadId,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rowUploads.length; i++) ...[
            Expanded(
              child: _buildPendingAlbumTile(
                rowUploads[i],
                isCurrentUpload: rowUploads[i].id == currentUploadId,
              ),
            ),
            if (i != rowUploads.length - 1) _albumSeparator(width: 1.5),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingAlbumTile(
    _PendingUpload upload, {
    required bool isCurrentUpload,
  }) {
    final progress = _uploadProgress(upload);
    final isWaiting = !upload.started && !upload.cancelled;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (upload.isVideo)
          _buildPendingAlbumVideoPreview(upload)
        else
          Image.memory(
            upload.bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPendingAlbumPlaceholder(
              Icons.image,
            ),
          ),
        Container(
            color: Colors.black.withValues(alpha: isWaiting ? 0.28 : 0.1)),
        if (isCurrentUpload)
          Positioned(
            top: 5,
            right: 5,
            child: _buildPendingAlbumUploadInfo(upload),
          ),
        Center(
          child: upload.failed
              ? const Icon(
                  Icons.error_rounded,
                  color: Colors.redAccent,
                  size: 34,
                )
              : upload.completed
                  ? Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.56),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: kWhite,
                        size: 28,
                      ),
                    )
                  : _PendingCancelProgressButton(
                      progress: progress,
                      backgroundColor: Colors.black.withValues(alpha: 0.56),
                      progressColor: Colors.white,
                      progressBackgroundColor:
                          Colors.white.withValues(alpha: 0.24),
                      iconColor: Colors.white,
                      onCancel: () {
                        upload.cancelled = true;
                        unawaited(_transferQueue.cancel(upload.id));
                        setState(() {});
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildPendingAlbumUploadInfo(_PendingUpload upload) {
    final progress = _uploadProgress(upload);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 6, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  color: Colors.white.withValues(alpha: 0.85),
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  strokeWidth: 2,
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${_pendingBytes(upload.uploadedBytes)} / ${_pendingBytes(upload.totalBytes)}',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingAlbumVideoPreview(_PendingUpload upload) {
    final thumbnail = upload.thumbnailBytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumbnail != null && thumbnail.isNotEmpty)
          Image.memory(
            thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _buildPendingAlbumPlaceholder(Icons.videocam),
          )
        else
          _buildPendingAlbumPlaceholder(Icons.videocam),
        Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white.withValues(alpha: 0.8),
            size: 34,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingAlbumPlaceholder(IconData icon) {
    return ColoredBox(
      color: kDarkGrey,
      child: Center(
        child: Icon(
          icon,
          color: kLightGrey,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildPendingUploadBubble(_PendingUpload upload) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(left: 60),
          child: upload.isAudio
              ? _PendingAudioUploadBubble(
                  upload: upload,
                  onCancel: () => _cancelPendingUpload(upload.id),
                  onRetry: () => _retryPendingUpload(upload),
                )
              : upload.isFile
                  ? _PendingFileUploadBubble(
                      upload: upload,
                      onCancel: () => _cancelPendingUpload(upload.id),
                      onRetry: () => _retryPendingUpload(upload),
                    )
                  : _PendingMediaUploadBubble(
                      upload: upload,
                      onRetry: () => _retryPendingUpload(upload),
                    ),
        ),
      ),
    );
  }

  bool _canDeleteMessage(Event event) {
    if (_room == null) return false;
    if (!_isStableMessageActionTarget(event)) return false;

    final isMyMessage = event.senderId == _myUserId;

    // Check if room is a channel
    final isChannel = _room!.isChannel;

    // In channels, members cannot delete messages (view only)
    if (isChannel && !_isAdmin()) {
      return false;
    }

    // In groups and DMs, users can delete their own messages
    // Admins can delete any message
    return isMyMessage || _isAdmin();
  }

  bool _isStableMessageActionTarget(Event event) {
    if (event.redacted || event.status.isSending) return false;
    return event.eventId.startsWith(r'$');
  }

  bool _ensureStableMessageActionTarget(Event event) {
    if (_isStableMessageActionTarget(event)) return true;
    _showSnackBar('Please wait until the message is sent.');
    return false;
  }

  bool _canReplyToMessage(Event event) {
    if (!_isStableMessageActionTarget(event)) return false;
    return event.type == EventTypes.Message ||
        event.type == EventTypes.Sticker ||
        event.type == _pollStartEventType;
  }

  bool _canReactToMessage(Event event) {
    return _canSendMessages && _isStableMessageActionTarget(event);
  }

  bool _canPinMessage(Event event) {
    return _canPinMessages() && _isStableMessageActionTarget(event);
  }

  bool _canEditMessage(Event event) {
    if (_room == null) return false;
    if (!_isStableMessageActionTarget(event)) return false;

    // Only the sender can edit their own messages
    final isMyMessage = event.senderId == _myUserId;

    // Can only edit text messages
    final isTextMessage = event.messageType == MessageTypes.Text ||
        event.messageType == MessageTypes.Notice ||
        event.messageType == MessageTypes.Emote;

    return isMyMessage && isTextMessage;
  }

  bool _canForwardMessage(Event event) {
    if (!_isStableMessageActionTarget(event)) return false;
    if (event.redacted) return false;
    if (event.type != EventTypes.Message && event.type != EventTypes.Sticker) {
      return false;
    }
    return event.content['msgtype'] is String;
  }

  bool _canDownloadAttachment(Event event) {
    if (!_isStableMessageActionTarget(event)) return false;
    if (event.redacted || event.type != EventTypes.Message) return false;

    final msgtype = _displayEventFor(event).messageType;
    return msgtype == MessageTypes.Image ||
        msgtype == MessageTypes.Video ||
        msgtype == MessageTypes.Audio ||
        msgtype == MessageTypes.File;
  }

  String? _copyableMessageText(Event event) {
    if (event.redacted || event.type != EventTypes.Message) return null;

    final displayEvent = _displayEventFor(event);
    final msgtype = displayEvent.messageType;
    final isCopyable = msgtype == MessageTypes.Text ||
        msgtype == MessageTypes.Notice ||
        msgtype == MessageTypes.Emote ||
        msgtype == MessageTypes.Image ||
        msgtype == MessageTypes.Video ||
        msgtype == MessageTypes.Audio ||
        msgtype == MessageTypes.File;
    if (!isCopyable) return null;

    final text = displayEvent
        .calcUnlocalizedBody(hideReply: true, hideEdit: true)
        .trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _copyMessageText(Event event) async {
    final text = _copyableMessageText(event);
    if (text == null) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        backgroundColor: kLimeGreen,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _downloadMessageAttachment(Event event) async {
    if (!_canDownloadAttachment(event)) {
      _showSnackBar('Please wait until the attachment is ready.');
      return;
    }
    await _downloadAndOpenFile(_displayEventFor(event));
  }

  Future<void> _shareMessageAttachment(Event event) async {
    if (!_canDownloadAttachment(event)) {
      _showSnackBar('Please wait until the attachment is ready.');
      return;
    }
    try {
      final displayEvent = _displayEventFor(event);
      await _downloadAttachmentWithQueue(
        displayEvent,
        activeLabel:
            'Preparing ${displayEvent.body.isNotEmpty ? displayEvent.body : 'file'}...',
        failurePrefix: 'Failed to share',
        onDownloaded: (file) => native_share.shareFile(
          file.bytes,
          file.name,
          mimeType: file.mimeType,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } on MatrixDownloadCancelledException {
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _isAdmin() {
    if (_room == null) return false;
    return GroupService.canModerateMembers(_ownPowerLevel());
  }

  bool _canPinMessages() {
    if (_room == null || _isDirectRoom) return false;
    return GroupService.canPinMessages(_ownPowerLevel());
  }

  bool get _isReadOnlyRestricted =>
      _ownRestriction != null &&
      _ownRestriction!.type == RestrictionType.readOnly &&
      !_ownRestriction!.isExpired;

  bool get _canSendMessages =>
      _room != null &&
      _room!.canSendEvent('m.room.message') &&
      RoomControlsService.canPerform(
        _room!,
        _myUserId,
        XmoRoomPermission.sendMessages,
      ) &&
      !_isReadOnlyRestricted;

  bool _canPerformRoomAction(XmoRoomPermission permission) {
    final room = _room;
    if (room == null) return false;
    return RoomControlsService.canPerform(room, _myUserId, permission);
  }

  String _permissionDeniedMessage(XmoRoomPermission permission) {
    switch (permission) {
      case XmoRoomPermission.sendMessages:
        return 'You do not have permission to send messages here.';
      case XmoRoomPermission.sendMedia:
        return 'You do not have permission to send media or files here.';
      case XmoRoomPermission.startCalls:
        return 'You do not have permission to start calls here.';
      case XmoRoomPermission.sendPolls:
        return 'You do not have permission to send polls here.';
      case XmoRoomPermission.sendStickers:
        return 'You do not have permission to send stickers here.';
    }
  }

  bool _ensureRoomActionAllowed(XmoRoomPermission permission) {
    if (_room == null) return false;
    if (_isReadOnlyRestricted &&
        (permission == XmoRoomPermission.sendMessages ||
            permission == XmoRoomPermission.sendMedia ||
            permission == XmoRoomPermission.sendPolls ||
            permission == XmoRoomPermission.sendStickers)) {
      _showSnackBar('You are in read-only mode in this group');
      return false;
    }
    if (!_canPerformRoomAction(permission)) {
      _showSnackBar(_permissionDeniedMessage(permission));
      return false;
    }
    return true;
  }

  bool _ensureSlowModeAllowed() {
    final room = _room;
    final timeline = _timeline;
    if (room == null || timeline == null) return true;
    final remaining = RoomControlsService.slowModeRemaining(
      room,
      _myUserId,
      timeline.events,
    );
    if (remaining <= Duration.zero) return true;
    final seconds =
        remaining.inSeconds + (remaining.inMilliseconds % 1000 == 0 ? 0 : 1);
    _showSnackBar('Slow mode is on. Wait ${seconds}s before sending again.');
    return false;
  }

  int _ownPowerLevel() {
    if (_room == null) return 0;
    for (final user in _room!.getParticipants()) {
      if (user.id == _myUserId) return user.powerLevel;
    }
    return _room!.ownPowerLevel;
  }

  void _showMentionProfileSheet(GroupMember member) {
    final isMe = member.userId == _myUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF26313A),
                Color(0xFF1F2831),
                Color(0xFF202529),
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StoryAvatar(
                  userName: member.displayName,
                  avatarUrl: member.avatarUrl,
                  size: 72,
                ),
                const SizedBox(height: 10),
                Text(
                  member.displayName,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MentionActionCard(
                        icon: Icons.chat_bubble_outline,
                        label: 'Message',
                        onTap: isMe
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _openDirectChatForMention(member);
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MentionActionCard(
                        icon: Icons.call_outlined,
                        label: 'Call',
                        onTap: isMe
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _startMentionCall(member, video: false);
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MentionActionCard(
                        icon: Icons.videocam_outlined,
                        label: 'Video',
                        onTap: isMe
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _startMentionCall(member, video: true);
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Room?> _directRoomForMention(GroupMember member) async {
    final roomId = await widget.matrixProvider.startDirectChat(member.userId);
    if (roomId == null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.matrixProvider.error ?? 'Could not open direct chat.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }

    return widget.matrixProvider.service.getRoomById(roomId);
  }

  Future<Room?> _directRoomForUserId(String userId) async {
    final localRoom = _localDirectRoomForUserId(userId);
    if (localRoom != null) return localRoom;

    final roomId = await widget.matrixProvider.startDirectChat(userId);
    if (roomId == null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.matrixProvider.error ?? 'Could not open direct chat.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }

    return _getRoomByIdAfterSync(roomId);
  }

  Room? _localDirectRoomForUserId(String userId) {
    var normalizedUserId = userId.trim();
    if (!normalizedUserId.startsWith('@')) {
      normalizedUserId = '@$normalizedUserId';
    }
    if (!normalizedUserId.contains(':')) {
      normalizedUserId = '$normalizedUserId:${MatrixService.matrixServerName}';
    }

    final service = widget.matrixProvider.service;
    final mappedRoomId =
        service.client.getDirectChatFromUserId(normalizedUserId);
    if (mappedRoomId != null) {
      final mappedRoom = service.getRoomById(mappedRoomId);
      if (mappedRoom != null && mappedRoom.membership == Membership.join) {
        return mappedRoom;
      }
    }

    for (final room in service.client.rooms) {
      if (room.membership != Membership.join) continue;
      if (service.getDirectPeerUserId(room) == normalizedUserId ||
          service.looksLikeLegacyDirectRoom(room, normalizedUserId)) {
        return room;
      }
    }

    return null;
  }

  Future<Room?> _getRoomByIdAfterSync(String roomId) async {
    var room = widget.matrixProvider.service.getRoomById(roomId);
    if (room != null) return room;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await widget.matrixProvider.service.client.oneShotSync();
      } catch (e) {
        debugPrint('[MatrixChatScreen] Failed to sync direct room: $e');
      }
      room = widget.matrixProvider.service.getRoomById(roomId);
      if (room != null) return room;
      await Future.delayed(const Duration(milliseconds: 250));
    }

    return null;
  }

  Future<void> _openDirectChatForMention(GroupMember member) async {
    final directRoom = await _directRoomForMention(member);
    if (!mounted || directRoom == null) return;
    if (directRoom.id == _room?.id) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatrixChatScreen(
          room: directRoom,
          matrixProvider: widget.matrixProvider,
        ),
      ),
    );
  }

  String _privateReplyPreview(Event event) {
    final displayEvent = _displayEventFor(event);
    final copyableText = _copyableMessageText(displayEvent);
    if (copyableText != null && copyableText.trim().isNotEmpty) {
      return _limitPrivateReplyPreview(copyableText.trim());
    }

    switch (displayEvent.messageType) {
      case MessageTypes.Image:
        return 'Photo';
      case MessageTypes.Video:
        return 'Video';
      case MessageTypes.Audio:
        return 'Audio';
      case MessageTypes.File:
        return displayEvent.body.trim().isEmpty ? 'File' : displayEvent.body;
      case MessageTypes.Text:
      case MessageTypes.Notice:
      case MessageTypes.Emote:
        return _limitPrivateReplyPreview(displayEvent.body.trim());
      default:
        return _limitPrivateReplyPreview(
          displayEvent.body.trim().isEmpty ? 'Message' : displayEvent.body,
        );
    }
  }

  String _limitPrivateReplyPreview(String text) {
    const maxLength = 180;
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  Future<Event?> _loadPrivateReplySourceEvent(PrivateReplyDraft draft) async {
    if (draft.sourceRoomId.isEmpty || draft.sourceEventId.isEmpty) {
      return null;
    }
    final sourceRoom =
        widget.matrixProvider.service.getRoomById(draft.sourceRoomId);
    if (sourceRoom == null) return null;

    try {
      return sourceRoom.getEventById(draft.sourceEventId);
    } catch (e) {
      debugPrint('[PrivateReply] Failed to load source event: $e');
      return null;
    }
  }

  Future<void> _replyPrivately(Event event) async {
    if (!_ensureStableMessageActionTarget(event)) return;
    final senderId = event.senderId;
    if (senderId.isEmpty || senderId == _myUserId) return;

    final directRoom = await _directRoomForUserId(senderId);
    if (!mounted) return;
    if (directRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open private chat. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (directRoom.id == _room?.id) return;

    final senderName = MatrixService.cleanName(senderId);
    final sourceName = _room == null
        ? 'group'
        : MatrixService.cleanName(
            _matrixService.getResolvedDisplayName(_room!),
          );
    final preview = _privateReplyPreview(event);
    final displayEvent = _displayEventFor(event);
    final privateReply = PrivateReplyDraft(
      sourceRoomId: _room?.id ?? '',
      sourceRoomName: sourceName,
      sourceEventId: event.eventId,
      senderId: senderId,
      senderName: senderName,
      preview: preview,
      msgtype: displayEvent.messageType,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatrixChatScreen(
          room: directRoom,
          matrixProvider: widget.matrixProvider,
          initialPrivateReply: privateReply,
        ),
      ),
    );
  }

  Future<void> _startMentionCall(
    GroupMember member, {
    required bool video,
  }) async {
    if (!_ensureRoomActionAllowed(XmoRoomPermission.startCalls)) return;

    final directRoom = await _directRoomForMention(member);
    if (!mounted || directRoom == null) return;

    try {
      await VoipService().startCall(directRoom, video: video);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Unable to start ${video ? 'video' : 'voice'} call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showMessageOptions(Event event) {
    final isPinned = _pinnedEvents.any((e) => e.eventId == event.eventId);
    final canEdit = _canEditMessage(event);
    final canDelete = _canDeleteMessage(event);
    final canReply = _canReplyToMessage(event);
    final canForward = _canForwardMessage(event);
    final canCopy = _copyableMessageText(event) != null;
    final canDownload = _canDownloadAttachment(event);
    final canReact = _canReactToMessage(event);
    final canPin = _canPinMessage(event);
    final canReplyPrivately = canReply &&
        _room != null &&
        !_isDirectRoom &&
        !_room!.isChannel &&
        event.senderId.isNotEmpty &&
        event.senderId != _myUserId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kDarkerGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canReply)
                  ListTile(
                    leading: const Icon(Icons.reply, color: kWhite),
                    title: Text(
                      'Reply',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _setReplyTo(event);
                    },
                  ),
                if (canReplyPrivately)
                  ListTile(
                    leading:
                        const Icon(Icons.chat_bubble_outline, color: kWhite),
                    title: Text(
                      'Reply privately',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _replyPrivately(event);
                    },
                  ),
                if (canCopy)
                  ListTile(
                    leading: const Icon(Icons.copy, color: kWhite),
                    title: Text(
                      'Copy',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _copyMessageText(event);
                    },
                  ),
                if (canReact)
                  ListTile(
                    leading:
                        const Icon(Icons.add_reaction_outlined, color: kWhite),
                    title: Text(
                      'Add Reaction',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showReactionPicker(event);
                    },
                  ),
                if (canForward)
                  ListTile(
                    leading: Transform.scale(
                      scaleX: -1,
                      child: const Icon(Icons.reply, color: kWhite),
                    ),
                    title: Text(
                      'Forward',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _forwardMessage(event);
                    },
                  ),
                if (canForward)
                  FutureBuilder<bool>(
                    initialData: _cachedSavedMessageStatus(event),
                    future: _isMessageSaved(event),
                    builder: (context, snapshot) {
                      final isSaved = snapshot.data == true;
                      return ListTile(
                        leading: Icon(
                          isSaved ? Icons.bookmark : Icons.bookmark_border,
                          color: kWhite,
                        ),
                        title: Text(
                          isSaved ? 'Saved' : 'Save',
                          style: GoogleFonts.inter(color: kWhite),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _saveMessage(event);
                        },
                      );
                    },
                  ),
                if (canDownload)
                  ListTile(
                    leading: const Icon(Icons.download, color: kWhite),
                    title: Text(
                      'Download',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _downloadMessageAttachment(event);
                    },
                  ),
                if (canDownload && !kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.share, color: kWhite),
                    title: Text(
                      'Share',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _shareMessageAttachment(event);
                    },
                  ),
                if (canEdit)
                  ListTile(
                    leading: const Icon(Icons.edit, color: kWhite),
                    title: Text(
                      'Edit Message',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _editMessage(event);
                    },
                  ),
                if (canPin)
                  ListTile(
                    leading: Icon(
                      isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                      color: kWhite,
                    ),
                    title: Text(
                      isPinned ? 'Unpin Message' : 'Pin Message',
                      style: GoogleFonts.inter(color: kWhite),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _togglePinMessage(event);
                    },
                  ),
                if (canDelete)
                  ListTile(
                    leading:
                        const Icon(Icons.delete_outline, color: Colors.red),
                    title: Text(
                      'Delete Message',
                      style: GoogleFonts.inter(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _deleteMessage(event);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _forwardMessage(Event event) async {
    final room = _room;
    if (room == null) return;
    if (!_ensureStableMessageActionTarget(event)) return;

    final selectedRooms = await showForwardMessageSheet(
      context: context,
      rooms: widget.matrixProvider.rooms,
      currentRoom: room,
    );

    if (selectedRooms == null || selectedRooms.isEmpty) return;

    try {
      for (final targetRoom in selectedRooms) {
        await widget.matrixProvider.service.forwardMessage(
          event: event,
          targetRoomId: targetRoom.id,
        );
      }
      if (!mounted) return;
      final count = selectedRooms.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Message forwarded'
                : 'Message forwarded to $count chats',
          ),
          backgroundColor: kLimeGreen,
        ),
      );
      widget.matrixProvider.refreshRooms();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to forward message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveMessage(Event event) async {
    if (!_ensureStableMessageActionTarget(event)) return;
    try {
      final savedRoom =
          await widget.matrixProvider.getOrCreateSavedMessagesRoom();
      await widget.matrixProvider.service.forwardMessage(
        event: event,
        targetRoomId: savedRoom.id,
      );
      _markMessageSaved(event);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message saved'),
          backgroundColor: kLimeGreen,
        ),
      );
      widget.matrixProvider.refreshRooms();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _savedMessageCacheKey(Event event) {
    return '${event.room.id}:${event.eventId}';
  }

  bool? _cachedSavedMessageStatus(Event event) {
    return _savedMessageStatusCache[_savedMessageCacheKey(event)];
  }

  void _markMessageSaved(Event event) {
    final key = _savedMessageCacheKey(event);
    _savedMessageStatusCache[key] = true;
    _savedMessageStatusFutures[key] = Future<bool>.value(true);
  }

  Future<bool> _isMessageSaved(Event event) {
    if (!_isStableMessageActionTarget(event)) return Future<bool>.value(false);
    final key = _savedMessageCacheKey(event);
    final cached = _savedMessageStatusCache[key];
    if (cached != null) return Future<bool>.value(cached);

    return _savedMessageStatusFutures.putIfAbsent(key, () async {
      final savedRoom = widget.matrixProvider.service.getSavedMessagesRoom();
      var isSaved = false;
      try {
        if (savedRoom != null) {
          final timeline = await savedRoom.getTimeline();
          for (final savedEvent in timeline.events) {
            if (savedEvent.redacted) continue;
            final forwarded = savedEvent.content['xmo.forwarded'];
            if (forwarded is! Map) continue;
            if (forwarded['event_id'] == event.eventId &&
                forwarded['room_id'] == event.room.id) {
              isSaved = true;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('[SavedMessages] Unable to check saved state: $e');
      }
      _savedMessageStatusCache[key] = isSaved;
      return isSaved;
    });
  }

  void _showReactionPicker(Event event) {
    if (!_ensureStableMessageActionTarget(event)) return;
    ReactionPicker.show(context, (emoji) async {
      try {
        await _toggleReaction(event, emoji);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reaction updated'),
              backgroundColor: kLimeGreen,
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add reaction: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }, selectedEmoji: _myReactionFor(event));
  }

  void _showReactionDetails(
    Event event,
    MessageReactionSummary selectedReaction,
  ) {
    final summaries = _reactionSummariesFor(event);
    final selected = summaries.firstWhere(
      (reaction) => reaction.emoji == selectedReaction.emoji,
      orElse: () => selectedReaction,
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: const BoxDecoration(
              color: Color(0xFF151515),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kMediumGrey,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      selected.emoji,
                      style: const TextStyle(fontSize: 26),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      selected.count == 1
                          ? '1 reaction'
                          : '${selected.count} reactions',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showReactionPicker(event);
                      },
                      child: Text(
                        'Change',
                        style: GoogleFonts.inter(
                          color: kLimeGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: selected.users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final user = selected.users[index];
                      final isMe = user.userId == _myUserId;
                      return Row(
                        children: [
                          StoryAvatar(
                            userName: user.displayName,
                            avatarUrl: user.avatarUrl,
                            size: 38,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isMe
                                  ? '${user.displayName} (You)'
                                  : user.displayName,
                              style: GoogleFonts.inter(
                                color: kWhite,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            selected.emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                try {
                                  await _toggleReaction(event, selected.emoji);
                                } catch (e) {
                                  if (mounted) {
                                    _showSnackBar('Failed to remove reaction');
                                  }
                                }
                              },
                              icon: const Icon(
                                Icons.close,
                                color: kLightGrey,
                                size: 20,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editMessage(Event event) async {
    if (!_ensureStableMessageActionTarget(event)) return;
    final currentText = _displayEventFor(event).calcUnlocalizedBody(
      hideReply: true,
      hideEdit: true,
    );
    final controller = TextEditingController(text: currentText);

    String? newText;
    try {
      newText = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kDarkerGrey,
          title: Text('Edit Message', style: GoogleFonts.inter(color: kWhite)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: kWhite),
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Enter new message',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: kDarkGrey,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text('Save', style: GoogleFonts.inter(color: kLimeGreen)),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }

    if (newText == null || newText.isEmpty || newText == currentText) return;

    try {
      await event.room.sendTextEvent(
        newText,
        editEventId: event.eventId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message edited'),
            backgroundColor: kLimeGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to edit message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _togglePinMessage(Event event) async {
    if (_room == null) return;
    if (!_ensureStableMessageActionTarget(event)) return;

    try {
      final groupService = GroupService(widget.matrixProvider.service);
      final isPinned = _pinnedEvents.any((e) => e.eventId == event.eventId);

      if (isPinned) {
        await groupService.unpinMessage(_room!.id, event.eventId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message unpinned'),
              backgroundColor: kLimeGreen,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        await groupService.pinMessage(_room!.id, event.eventId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message pinned'),
              backgroundColor: kLimeGreen,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      // Reload pinned messages
      _loadPinnedMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pin/unpin message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMessage(Event event) async {
    if (_room == null) return;
    if (!_ensureStableMessageActionTarget(event)) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text(
          'Delete Message?',
          style: GoogleFonts.inter(color: kWhite),
        ),
        content: Text(
          'This message will be deleted for everyone.',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: kLightGrey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final wasPinned = _pinnedEvents.any((e) => e.eventId == event.eventId);
      await event.redactEvent();
      if (wasPinned) {
        if (mounted) {
          setState(() {
            _pinnedEvents.removeWhere((e) => e.eventId == event.eventId);
            _pinnedBannerIndex = null;
          });
        }
        if (_canPinMessages()) {
          unawaited(_cleanupStalePinnedMessages([event.eventId]));
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            backgroundColor: kLimeGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');

    if (hour == 0) {
      return '12:$minute AM';
    } else if (hour < 12) {
      return '$hour:$minute AM';
    } else if (hour == 12) {
      return '12:$minute PM';
    } else {
      return '${hour - 12}:$minute PM';
    }
  }

  Widget _buildMessageStatus(Event event) {
    if (_isDirectRoom) {
      if (event.status.isSending) {
        return const ReadReceipt(status: ReadReceiptStatus.sending);
      }

      if (event.status == EventStatus.sent) {
        return const ReadReceipt(status: ReadReceiptStatus.sent);
      }

      final isRead = _directChatService.isMessageRead(
        event,
        _room!,
        timelineEvents: _timeline?.events,
      );

      if (isRead) {
        return const ReadReceipt(status: ReadReceiptStatus.read);
      }

      return const ReadReceipt(status: ReadReceiptStatus.delivered);
    }

    // For groups/channels, show the same delivered double-tick style.
    return const ReadReceipt(status: ReadReceiptStatus.delivered);
  }

  Future<void> _handleDeleteChat() async {
    if (_room == null) return;
    try {
      await _room!.leave();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleLeaveRoom() async {
    if (_room == null) return;
    try {
      await _room!.leave();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Left the room successfully'),
            backgroundColor: kLimeGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to leave room: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteGroup() async {
    if (_room == null) return;
    final isChannel = _room!.isChannel;
    final roomType = isChannel ? 'channel' : 'group';
    final roomTypeTitle = isChannel ? 'Channel' : 'Group';

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text(
          'Delete $roomTypeTitle?',
          style: GoogleFonts.inter(color: kWhite),
        ),
        content: Text(
          'This will permanently delete the $roomType for all ${isChannel ? 'subscribers' : 'members'}. This action cannot be undone.',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: kLightGrey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: kLimeGreen,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Deleting $roomType...',
                  style: GoogleFonts.inter(color: kWhite, fontSize: 13),
                ),
              ],
            ),
            backgroundColor: kDarkerGrey,
            duration: const Duration(seconds: 30),
          ),
        );
      }

      // Delete the group using the service directly
      final groupService = GroupService(widget.matrixProvider.service);
      await groupService.deleteGroup(_room!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$roomTypeTitle deleted successfully'),
            backgroundColor: kLimeGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete $roomType: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _amplitudeSub?.cancel();
    unawaited(_audioRecorder.dispose());
    _composerController.dispose();
    _timelineController.dispose();
    _scrollCtrl.removeListener(_handleChatScroll);
    _scrollCtrl.dispose();
    _mentionAutocomplete.dispose();
    _eventSub?.cancel();
    _typingSub?.cancel();
    _typingTimer?.cancel();
    _highlightTimer?.cancel();
    _readMarkerDebounce?.cancel();
    _sharedMediaIndexDebounce?.cancel();
    _stateRefreshDebounce?.cancel();
    _mediaHandler.clearCache();
    super.dispose();
  }

  Widget _buildOngoingGroupCallBanner(Room room) {
    return ValueListenableBuilder<int>(
      valueListenable: VoipService().callStateVersion,
      builder: (context, _, __) {
        final groupCall = VoipService().ongoingGroupCallForRoom(room);
        final incomingGroupCall = VoipService().incomingGroupCall.value;
        if (groupCall == null ||
            groupCall.terminated ||
            _dismissedGroupCallBannerIds.contains(groupCall.groupCallId) ||
            VoipService().isGroupCallRejected(groupCall) ||
            incomingGroupCall == groupCall ||
            VoipService().isInCall ||
            VoipService().activeGroupCall == groupCall) {
          return const SizedBox.shrink();
        }

        final isVideo = groupCall.type == GroupCallType.Video;
        final title = isVideo ? 'Ongoing video call' : 'Ongoing voice call';
        final roomTitle = MatrixService.cleanName(
          MatrixService().getResolvedDisplayName(groupCall.room),
        );
        final displayName =
            roomTitle.trim().isEmpty ? 'Group' : roomTitle.trim();

        return SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262728),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: kBlack.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      StoryAvatar(
                        userName: displayName,
                        avatarUrl: groupCall.room.avatar?.toString(),
                        size: 46,
                        fallbackIcon: Icons.group,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: kWhite,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              style: GoogleFonts.inter(
                                color: kWhite.withValues(alpha: 0.68),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: kAudioBlue,
                          foregroundColor: kWhite,
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: () async {
                          try {
                            await VoipService()
                                .answerIncomingGroupCall(groupCall);
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Unable to join call: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        child: Text(
                          'Join',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Dismiss',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        icon: const Icon(
                          Icons.close,
                          color: kWhite,
                          size: 20,
                        ),
                        onPressed: () {
                          VoipService().rejectGroupCall(groupCall);
                          setState(() {
                            _dismissedGroupCallBannerIds.add(
                              groupCall.groupCallId,
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _visibleMessages();
    final messageItems = _buildMessageListItems(messages);
    final historyLoaderCount = _loadingHistory ? 1 : 0;
    final orderedPinnedEvents = _orderedPinnedEvents();
    final pinnedBannerIndex = _currentPinnedBannerIndex(orderedPinnedEvents);

    return IncomingCallFullscreenScope(
      roomId: _room?.id,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: kBlack,
            appBar: _room != null
                ? ChatAppBar(
                    room: _room!,
                    onBack: () => Navigator.pop(context),
                    onDeleteChat: _handleDeleteChat,
                    onLeaveRoom: _handleLeaveRoom,
                    onDeleteGroup: _handleDeleteGroup,
                    matrixProvider: widget.matrixProvider,
                  )
                : AppBar(
                    backgroundColor: kBlack,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, color: kWhite),
                      onPressed: () => Navigator.pop(context),
                    ),
                    title: Text(
                      widget.previewChannel!.name ??
                          widget.previewChannel!.roomId,
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
            body: Stack(
              children: [
                const Positioned.fill(
                  child: RepaintBoundary(child: ChatSpaceBackground()),
                ),
                Column(
                  children: [
                    // Pinned Messages Banner
                    if (orderedPinnedEvents.isNotEmpty)
                      PinnedMessagesBanner(
                        pinnedEvents: orderedPinnedEvents,
                        currentEvent: orderedPinnedEvents[pinnedBannerIndex],
                        currentPosition: pinnedBannerIndex + 1,
                        onTap: _jumpToPinnedMessage,
                      ),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child:
                                  CircularProgressIndicator(color: kLimeGreen),
                            )
                          : messages.isEmpty &&
                                  _pendingUploads.isEmpty &&
                                  _pendingAlbumUploads.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.chat_bubble_outline,
                                        color: kMediumGrey,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No messages yet. Say hello!',
                                        style: GoogleFonts.inter(
                                          color: kLightGrey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : RepaintBoundary(
                                  child: ListView.builder(
                                    controller: _scrollCtrl,
                                    // ignore: deprecated_member_use
                                    cacheExtent: 900,
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 0,
                                      vertical: 8,
                                    ),
                                    itemCount: historyLoaderCount +
                                        messageItems.length +
                                        _pendingAlbumUploads.length +
                                        _pendingUploads.length,
                                    itemBuilder: (_, i) {
                                      if (historyLoaderCount == 1 && i == 0) {
                                        return _buildHistoryLoadingIndicator();
                                      }
                                      final contentIndex =
                                          i - historyLoaderCount;
                                      if (contentIndex < messageItems.length) {
                                        final item = messageItems[contentIndex];
                                        return RepaintBoundary(
                                          key: _messageListItemKey(item),
                                          child: item.albumEvents == null
                                              ? _buildBubble(item.event!)
                                              : _buildMediaAlbumBubble(
                                                  item.albumEvents!,
                                                ),
                                        );
                                      }
                                      final pendingAlbumIndex =
                                          contentIndex - messageItems.length;
                                      if (pendingAlbumIndex <
                                          _pendingAlbumUploads.length) {
                                        final pendingAlbum =
                                            _pendingAlbumUploads[
                                                pendingAlbumIndex];
                                        return RepaintBoundary(
                                          key: ValueKey(
                                            'pending_album_${pendingAlbum.id}',
                                          ),
                                          child: _buildPendingAlbumUploadBubble(
                                            pendingAlbum,
                                          ),
                                        );
                                      }
                                      final pendingUpload = _pendingUploads[
                                          pendingAlbumIndex -
                                              _pendingAlbumUploads.length];
                                      return RepaintBoundary(
                                        key: ValueKey(
                                          'pending_upload_${pendingUpload.id}',
                                        ),
                                        child: _buildPendingUploadBubble(
                                          pendingUpload,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                    ),
                    // Reply Preview
                    if (_replyToEvent != null)
                      ReplyPreview(
                        replyToEvent: _replyToEvent!,
                        onCancel: _cancelReply,
                      ),
                    if (_privateReplyDraft != null)
                      _PrivateReplyComposerPreview(
                        draft: _privateReplyDraft!,
                        onCancel: _cancelPrivateReply,
                        loadSourceEvent: _loadPrivateReplySourceEvent,
                        loadImageBytes: _mediaHandler.loadImageBytes,
                        loadVideoThumbnail: _mediaHandler.loadVideoThumbnail,
                      ),
                    // Mention Autocomplete
                    ValueListenableBuilder<_MentionAutocompleteState>(
                      valueListenable: _mentionAutocomplete,
                      builder: (context, mention, _) {
                        if (!mention.visible || _groupMembers.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return MentionAutocomplete(
                          members: _groupMembers,
                          query: mention.query,
                          onMemberSelected: _insertMention,
                        );
                      },
                    ),
                    // Typing Indicator (Direct Chats Only)
                    if (_isDirectRoom && _typingUsers.isNotEmpty)
                      TypingIndicator(userName: _typingUsers.first),
                    if (_room == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 8, 28, 14),
                        child: SizedBox(
                          width: math.min(
                            360,
                            MediaQuery.sizeOf(context).width - 56,
                          ),
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _joinPreviewChannel,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kLimeGreen,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: Text(
                              _getJoinButtonText(),
                              style: GoogleFonts.inter(
                                color: kBlack,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (_room!.canSendEvent('m.room.message'))
                      ChatInputBar(
                        textController: _textCtrl,
                        textFocusNode: _textFocusNode,
                        uploading: _isUploadBusy,
                        recording: _recording,
                        recordingPaused: _recordingPaused,
                        recordingDuration: _recordingDuration,
                        recordingWaveform: _recordingWaveform,
                        enabled: _canSendMessages,
                        disabledText: _isReadOnlyRestricted
                            ? 'Read-only mode'
                            : 'You cannot send messages',
                        onSend: _sendMessage,
                        onShowEmojiPicker: _showComposerEmojiPicker,
                        onShowAttachmentSheet: _showAttachmentSheet,
                        onStartRecording: _startAudioRecording,
                        onCancelRecording: _cancelAudioRecording,
                        onToggleRecordingPause: _toggleAudioRecordingPause,
                        onStopAndSendRecording: _stopAndSendAudioRecording,
                      )
                    else
                      Container(
                        width: double.infinity,
                        color: kDarkerGrey,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            _getJoinButtonText(),
                            style: GoogleFonts.inter(
                              color: kMediumGrey,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                _buildJumpToLatestButton(),
              ],
            ),
          ),
          if (_room != null && !_isDirectRoom && !_room!.isChannel)
            _buildOngoingGroupCallBanner(_room!),
        ],
      ),
    );
  }
}

class _PrivateReplyComposerPreview extends StatelessWidget {
  final PrivateReplyDraft draft;
  final VoidCallback onCancel;
  final Future<Event?> Function(PrivateReplyDraft) loadSourceEvent;
  final Future<Uint8List?> Function(Event, {bool getThumbnail}) loadImageBytes;
  final Future<Uint8List?> Function(Event) loadVideoThumbnail;

  const _PrivateReplyComposerPreview({
    required this.draft,
    required this.onCancel,
    required this.loadSourceEvent,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Event?>(
      future: loadSourceEvent(draft),
      builder: (context, snapshot) {
        final sourceEvent = snapshot.data;
        final preview = sourceEvent == null
            ? draft.preview
            : _privateReplyPreviewText(
                sourceEvent,
                fallback: draft.preview,
              );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: kDarkerGrey,
            border: Border(
              top: BorderSide(color: kMediumGrey, width: 1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 40,
                decoration: BoxDecoration(
                  color: kLimeGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              _PrivateReplyMediaPreview(
                event: sourceEvent,
                fallbackMsgtype: draft.msgtype,
                isMe: true,
                loadImageBytes: loadImageBytes,
                loadVideoThumbnail: loadVideoThumbnail,
              ),
              if (_privateReplyHasMediaPreview(sourceEvent, draft.msgtype))
                const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      draft.senderName,
                      style: GoogleFonts.inter(
                        color: kLimeGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      style: GoogleFonts.inter(
                        color: kLightGrey,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: kLightGrey, size: 20),
                onPressed: onCancel,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }

  String _privateReplyPreviewText(Event event, {required String fallback}) {
    switch (event.messageType) {
      case MessageTypes.Image:
        return 'Photo';
      case MessageTypes.Video:
        return 'Video';
      case MessageTypes.Audio:
        return 'Audio';
      case MessageTypes.File:
        return event.body.trim().isEmpty ? 'File' : event.body.trim();
      default:
        return fallback.trim().isEmpty ? 'Message' : fallback.trim();
    }
  }
}

bool _privateReplyHasMediaPreview(Event? event, String fallbackMsgtype) {
  final msgtype = event?.messageType ?? fallbackMsgtype;
  return msgtype == MessageTypes.Image ||
      msgtype == MessageTypes.Video ||
      msgtype == MessageTypes.Audio ||
      msgtype == MessageTypes.File;
}

Uint8List? _privateReplyCachedMediaBytes(Event event, bool isImage) {
  return isImage
      ? MediaHandler.getCachedImageBytes(event.eventId, getThumbnail: true)
      : MediaHandler.getCachedThumbnail(event.eventId);
}

class _PrivateReplyMediaPreview extends StatelessWidget {
  final Event? event;
  final String fallbackMsgtype;
  final bool isMe;
  final Future<Uint8List?> Function(Event, {bool getThumbnail}) loadImageBytes;
  final Future<Uint8List?> Function(Event) loadVideoThumbnail;

  const _PrivateReplyMediaPreview({
    required this.event,
    required this.fallbackMsgtype,
    required this.isMe,
    required this.loadImageBytes,
    required this.loadVideoThumbnail,
  });

  @override
  Widget build(BuildContext context) {
    final msgtype = event?.messageType ?? fallbackMsgtype;
    if (msgtype == MessageTypes.Image || msgtype == MessageTypes.Video) {
      final source = event;
      final isImage = msgtype == MessageTypes.Image;
      final cachedBytes = source == null
          ? null
          : _privateReplyCachedMediaBytes(source, isImage);
      final thumbFuture = source == null || cachedBytes != null
          ? null
          : isImage
              ? loadImageBytes(source, getThumbnail: true)
              : loadVideoThumbnail(source);

      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1A2A1A) : kDarkGrey,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<Uint8List?>(
          initialData: cachedBytes,
          future: thumbFuture,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _PrivateReplyTypeIcon(
                      msgtype: msgtype,
                      isMe: isMe,
                    ),
                  ),
                  if (msgtype == MessageTypes.Video)
                    Container(
                      color: Colors.black.withValues(alpha: 0.18),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                ],
              );
            }
            return _PrivateReplyTypeIcon(msgtype: msgtype, isMe: isMe);
          },
        ),
      );
    }

    if (msgtype == MessageTypes.Audio || msgtype == MessageTypes.File) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1A2A1A) : kDarkGrey,
          borderRadius: BorderRadius.circular(10),
        ),
        child: _PrivateReplyTypeIcon(msgtype: msgtype, isMe: isMe),
      );
    }

    return const SizedBox.shrink();
  }
}

class _PrivateReplyTypeIcon extends StatelessWidget {
  final String msgtype;
  final bool isMe;

  const _PrivateReplyTypeIcon({
    required this.msgtype,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (msgtype) {
      MessageTypes.Image => Icons.image_rounded,
      MessageTypes.Video => Icons.play_arrow_rounded,
      MessageTypes.Audio => Icons.headphones_rounded,
      MessageTypes.File => Icons.insert_drive_file_rounded,
      _ => Icons.chat_bubble_rounded,
    };

    return Icon(
      icon,
      color: isMe ? kLimeGreen : kLightGrey,
      size: 20,
    );
  }
}

class _MentionActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _MentionActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF363A3E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: kLimeGreen, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MentionAutocompleteState {
  final bool visible;
  final String query;

  const _MentionAutocompleteState._({
    required this.visible,
    required this.query,
  });

  static const hidden = _MentionAutocompleteState._(
    visible: false,
    query: '',
  );

  factory _MentionAutocompleteState.visible(String query) {
    return _MentionAutocompleteState._(
      visible: true,
      query: query,
    );
  }
}

class _PollAnswer {
  final String id;
  final String text;

  const _PollAnswer({
    required this.id,
    required this.text,
  });
}

class _PollOptionTile extends StatelessWidget {
  final String text;
  final int count;
  final int total;
  final bool selected;
  final VoidCallback? onTap;

  const _PollOptionTile({
    required this.text,
    required this.count,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: kDarkGrey,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? kLimeGreen : kMediumGrey,
                width: selected ? 1.2 : 0.8,
              ),
            ),
          ),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: kLimeGreen.withValues(alpha: selected ? 0.3 : 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? kLimeGreen : kLightGrey,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: GoogleFonts.inter(
                      color: selected ? kLimeGreen : kLightGrey,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PollComposeResult {
  final String question;
  final List<String> options;

  const _PollComposeResult({
    required this.question,
    required this.options,
  });
}

class _PollComposerDialog extends StatefulWidget {
  const _PollComposerDialog();

  @override
  State<_PollComposerDialog> createState() => _PollComposerDialogState();
}

class _PollComposerDialogState extends State<_PollComposerDialog> {
  final _questionController = TextEditingController();
  final _optionControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 6) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    final controller = _optionControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  void _submit() {
    final question = _questionController.text.trim();
    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .where((option) => option.isNotEmpty)
        .toList(growable: false);
    if (question.isEmpty || options.length < 2) {
      return;
    }
    Navigator.pop(
      context,
      _PollComposeResult(question: question, options: options),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kDarkerGrey,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _questionController,
            ..._optionControllers,
          ]),
          builder: (context, _) {
            final submitEnabled = _questionController.text.trim().isNotEmpty &&
                _optionControllers
                        .where(
                          (controller) => controller.text.trim().isNotEmpty,
                        )
                        .length >=
                    2;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create Poll',
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _PollTextField(
                  controller: _questionController,
                  hint: 'Question',
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < _optionControllers.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _PollTextField(
                          controller: _optionControllers[i],
                          hint: 'Option ${i + 1}',
                        ),
                      ),
                      if (_optionControllers.length > 2)
                        IconButton(
                          onPressed: () => _removeOption(i),
                          icon: const Icon(
                            Icons.close,
                            color: kLightGrey,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        _optionControllers.length >= 6 ? null : _addOption,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add option'),
                    style: TextButton.styleFrom(
                      foregroundColor: kLimeGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ElevatedButton(
                  onPressed: submitEnabled ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kWhite,
                    disabledBackgroundColor: kMediumGrey,
                    foregroundColor: kBlack,
                    disabledForegroundColor: kLightGrey,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: Text(
                    'Send Poll',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PollTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _PollTextField({
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(color: kWhite, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF2C2C2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kWhite, width: 1),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    );
  }
}

class _PendingUpload {
  final String id;
  final Uint8List bytes;
  Uint8List? thumbnailBytes;
  final String fileName;
  final String mimeType;
  final bool isVideo;
  final bool isAudio;
  final bool isFile;
  final bool isVoiceMessage;
  int totalBytes;
  int uploadedBytes = 0;
  String? transferJobId;
  Future<void>? previewHydration;
  bool started = false;
  bool completed = false;
  bool failed = false;
  bool cancelled = false;
  String? error;
  final DateTime createdAt;
  int? width;
  int? height;
  int? durationMs;

  _PendingUpload({
    required this.id,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.isVideo,
    this.isAudio = false,
    this.isFile = false,
    this.isVoiceMessage = false,
    required this.totalBytes,
    required this.createdAt,
    this.transferJobId,
    this.thumbnailBytes,
    this.durationMs,
  });
}

class _PendingAlbumUpload {
  final String id;
  final List<_PendingUpload> uploads;
  final DateTime createdAt;
  String? currentUploadId;
  bool cancelled = false;

  _PendingAlbumUpload({
    required this.id,
    required this.uploads,
    required this.createdAt,
  });
}

class _MessageListItem {
  final Event? event;
  final List<Event>? albumEvents;

  const _MessageListItem._({this.event, this.albumEvents});

  factory _MessageListItem.message(Event event) {
    return _MessageListItem._(event: event);
  }

  factory _MessageListItem.album(List<Event> events) {
    return _MessageListItem._(albumEvents: List<Event>.unmodifiable(events));
  }
}

double? _uploadProgress(_PendingUpload upload) {
  if (upload.totalBytes <= 0) return null;
  return (upload.uploadedBytes / upload.totalBytes).clamp(0.0, 1.0);
}

String _pendingBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
}

class _DownloadSnackBarContent extends StatelessWidget {
  final String jobId;
  final List<TransferJob> initialJobs;
  final Stream<List<TransferJob>> stream;
  final VoidCallback onCancel;

  const _DownloadSnackBarContent({
    required this.jobId,
    required this.initialJobs,
    required this.stream,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransferJob>>(
      stream: stream,
      initialData: initialJobs,
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const <TransferJob>[];
        final job = jobs.cast<TransferJob?>().firstWhere(
              (item) => item?.id == jobId,
              orElse: () => null,
            );
        final downloaded = job?.uploadedBytes ?? 0;
        final total = job?.totalBytes ?? 0;
        final progress =
            total > 0 ? (downloaded / total).clamp(0.0, 1.0).toDouble() : null;
        final sizeText = total > 0
            ? '${_pendingBytes(downloaded)} / ${_pendingBytes(total)}'
            : '${_pendingBytes(downloaded)} / --';

        return SizedBox(
          height: 48,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final progressWidth = constraints.maxWidth * (progress ?? 0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: kWhite),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: progressWidth,
                      height: double.infinity,
                      color: kLimeGreen,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Downloading',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: kBlack,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          sizeText,
                          style: GoogleFonts.inter(
                            color: kBlack.withValues(alpha: 0.76),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 18),
                        TextButton(
                          onPressed: onCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: kBlack,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              color: kBlack,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

String _pendingDuration(int durationMs) {
  final duration = Duration(milliseconds: durationMs);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _pendingClock(DateTime time) {
  final hour =
      time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

class _PendingAudioUploadBubble extends StatelessWidget {
  final _PendingUpload upload;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  const _PendingAudioUploadBubble({
    required this.upload,
    required this.onCancel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _uploadProgress(upload);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = math.min(330.0, math.max(160.0, screenWidth * 0.78));
    final minBubbleWidth = math.min(280.0, maxBubbleWidth);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: const BoxDecoration(
        color: Color(0xFF1A2A1A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minBubbleWidth,
          maxWidth: maxBubbleWidth,
        ),
        child: SizedBox(
          height: 58,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 48,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      upload.failed
                          ? _PendingRetryButton(onRetry: onRetry)
                          : _PendingCancelProgressButton(
                              progress: progress,
                              onCancel: onCancel,
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: VoiceWaveform(
                          color: kLimeGreen,
                          inactiveColor: kLimeGreen.withValues(alpha: 0.25),
                          progress: 0,
                          height: 30,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Row(
                  children: [
                    const SizedBox(width: 54),
                    Text(
                      upload.durationMs != null && upload.durationMs! > 0
                          ? _pendingDuration(upload.durationMs!)
                          : '00:00',
                      style: GoogleFonts.inter(
                        color: kLimeGreen.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _PendingSmallTime(upload: upload),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingFileUploadBubble extends StatelessWidget {
  final _PendingUpload upload;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  const _PendingFileUploadBubble({
    required this.upload,
    required this.onCancel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _uploadProgress(upload);
    final attachmentType = attachmentTypeFor(
      mimeType: upload.mimeType,
      fileName: upload.fileName,
    );
    final bubbleWidth = math.min(
      280.0,
      math.max(180.0, MediaQuery.sizeOf(context).width * 0.72),
    );

    return Container(
      width: bubbleWidth,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1A2A1A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              upload.failed
                  ? _PendingRetryButton(onRetry: onRetry)
                  : _PendingCancelProgressButton(
                      progress: progress,
                      onCancel: onCancel,
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      upload.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: kLimeGreen,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_pendingBytes(upload.totalBytes)} • ',
                          style: GoogleFonts.inter(
                            color: kLimeGreen.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          attachmentType.label,
                          style: GoogleFonts.inter(
                            color: kLimeGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _PendingSmallTime(upload: upload),
          ),
        ],
      ),
    );
  }
}

class _PendingCancelProgressButton extends StatelessWidget {
  final double? progress;
  final VoidCallback onCancel;
  final Color backgroundColor;
  final Color progressColor;
  final Color progressBackgroundColor;
  final Color iconColor;

  const _PendingCancelProgressButton({
    required this.progress,
    required this.onCancel,
    this.backgroundColor = kLimeGreen,
    this.progressColor = kBlack,
    this.progressBackgroundColor = const Color(0x52000000),
    this.iconColor = kBlack,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: progressColor,
                backgroundColor: progressBackgroundColor,
              ),
            ),
            Icon(
              Icons.close_rounded,
              color: iconColor,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingRetryButton extends StatelessWidget {
  final VoidCallback onRetry;

  const _PendingRetryButton({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.92),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.refresh_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }
}

class _PendingSmallTime extends StatelessWidget {
  final _PendingUpload upload;

  const _PendingSmallTime({required this.upload});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _pendingClock(upload.createdAt),
          style: GoogleFonts.inter(
            color: kLimeGreen.withValues(alpha: 0.6),
            fontSize: 10,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.access_time_rounded,
          color: kLimeGreen.withValues(alpha: 0.6),
          size: 12,
        ),
      ],
    );
  }
}

class _PendingMediaUploadBubble extends StatelessWidget {
  final _PendingUpload upload;
  final VoidCallback onRetry;

  const _PendingMediaUploadBubble({
    required this.upload,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final size = upload.isVideo
        ? _displayVideoSizeForRatio(context, _aspectRatio)
        : _displayImageSizeForRatio(context, _aspectRatio);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (upload.isVideo)
              _buildVideoPreview()
            else
              Image.memory(
                upload.bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(Icons.image),
              ),
            Positioned(
              top: 6,
              left: 6,
              child: _buildUploadInfo(),
            ),
            if (upload.failed)
              Center(
                child: _PendingRetryButton(onRetry: onRetry),
              ),
            Positioned(
              bottom: 8,
              right: 8,
              child: _buildPendingTime(),
            ),
          ],
        ),
      ),
    );
  }

  double get _aspectRatio {
    final width = upload.width;
    final height = upload.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 16 / 9;
  }

  Widget _buildVideoPreview() {
    final thumbnail = upload.thumbnailBytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumbnail != null && thumbnail.isNotEmpty)
          Image.memory(
            thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholder(Icons.videocam),
          )
        else
          _buildPlaceholder(Icons.videocam),
        Center(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(IconData icon) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C2B1C), Color(0xFF111111)],
        ),
      ),
      child: Icon(
        icon,
        color: Colors.white24,
        size: 64,
      ),
    );
  }

  Widget _buildUploadInfo() {
    final progress = upload.totalBytes > 0
        ? (upload.uploadedBytes / upload.totalBytes).clamp(0.0, 1.0)
        : null;
    final lines = <Widget>[];
    if (upload.isVideo && upload.durationMs != null && upload.durationMs! > 0) {
      lines.add(Text(
        _formatDuration(upload.durationMs!),
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ));
      lines.add(const SizedBox(height: 1));
    }
    lines.add(Text(
      '${_formatBytes(upload.uploadedBytes)} / ${_formatBytes(upload.totalBytes)}',
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.1,
      ),
    ));

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 6, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  color: Colors.white.withValues(alpha: 0.85),
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  strokeWidth: 2,
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: lines,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTime() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatClock(upload.createdAt),
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.access_time_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            size: 14,
          ),
        ],
      ),
    );
  }

  Size _displayImageSizeForRatio(BuildContext context, double aspectRatio) {
    final maxWidth = math.min(
      292.0,
      math.max(160.0, MediaQuery.sizeOf(context).width * 0.76),
    );
    return _displaySizeForRatio(
      aspectRatio,
      maxWidth: maxWidth,
      maxHeight: math.min(336.0, math.max(120.0, maxWidth * 1.15)),
    );
  }

  Size _displayVideoSizeForRatio(BuildContext context, double aspectRatio) {
    final maxWidth = math.min(
      292.0,
      math.max(160.0, MediaQuery.sizeOf(context).width * 0.76),
    );
    return _displaySizeForRatio(
      aspectRatio,
      maxWidth: maxWidth,
      maxHeight: math.min(360.0, math.max(140.0, maxWidth * 1.23)),
    );
  }

  Size _displaySizeForRatio(
    double aspectRatio, {
    required double maxWidth,
    required double maxHeight,
  }) {
    const minReadableHeight = 96.0;

    final ratio =
        aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 9;

    double width;
    double height;

    if (ratio >= 1) {
      width = maxWidth;
      height = width / ratio;
      if (height > maxHeight) {
        height = maxHeight;
        width = height * ratio;
      }
    } else {
      height = maxHeight;
      width = height * ratio;
      if (width > maxWidth) {
        width = maxWidth;
        height = width / ratio;
      }
    }

    if (height < minReadableHeight) {
      height = minReadableHeight;
      width = (height * ratio).clamp(140.0, maxWidth).toDouble();
    }

    return Size(width, height);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  static String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatClock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}
