import 'dart:async';
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
import 'package:record/record.dart';
import '../theme.dart';
import '../providers/matrix_provider.dart';
import '../services/matrix_service.dart';
import '../services/group_service.dart';
import '../services/app_settings_service.dart';
import '../widgets/matrix_chat/fullscreen_image_viewer.dart';
import '../widgets/matrix_chat/fullscreen_video_player.dart';
import '../widgets/matrix_chat/reply_preview.dart';
import '../widgets/matrix_chat/pinned_messages_banner.dart';
import '../widgets/matrix_chat/mention_autocomplete.dart';
import '../widgets/direct_chat/typing_indicator.dart';
import '../widgets/direct_chat/message_reactions.dart';
import '../widgets/direct_chat/read_receipt.dart';
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
import 'matrix_chat/forward_message_sheet.dart';
import 'matrix_chat/media_handler.dart';
import 'matrix_chat/message_widgets.dart';
import 'matrix_chat/pinned_messages_sheet.dart';
import 'native_share_stub.dart' if (dart.library.io) 'native_share.dart'
    as native_share;

// Web download helper
import 'web_download_stub.dart' if (dart.library.js_interop) 'web_download.dart'
    as web_download;

// Web video view

/// Real-time Matrix chat screen for a given Room
class MatrixChatScreen extends StatefulWidget {
  final Room? room;
  final PublicRoomsChunk? previewChannel;
  final MatrixProvider matrixProvider;

  const MatrixChatScreen({
    super.key,
    this.room,
    this.previewChannel,
    required this.matrixProvider,
  }) : assert(room != null || previewChannel != null);

  @override
  State<MatrixChatScreen> createState() => _MatrixChatScreenState();
}

class _MatrixChatScreenState extends State<MatrixChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timeline? _timeline;
  bool _loading = true;
  bool _hasText = false;
  bool _uploading = false;
  bool _recording = false;
  bool _recordingPaused = false;
  Duration _recordingDuration = Duration.zero;
  List<double> _recordingWaveform = const [];
  bool? _previewIsChannel;
  StreamSubscription<EventUpdate>? _eventSub;
  late MediaHandler _mediaHandler;
  Event? _replyToEvent; // Track which message we're replying to
  List<Event> _pinnedEvents = []; // Track pinned messages
  List<GroupMember> _groupMembers = []; // Track group members for mentions
  MemberRestriction? _ownRestriction;
  String _mentionQuery = ''; // Current mention query
  bool _showMentionAutocomplete = false; // Show mention autocomplete
  List<String> _typingUsers = []; // Track typing users
  late DirectChatService _directChatService;
  Timer? _typingTimer; // Timer for sending typing indicators
  Timer? _recordingTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  DateTime? _recordingStartedAt;
  Duration _recordingAccumulatedDuration = Duration.zero;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedEventId;
  Timer? _highlightTimer;
  final List<_PendingUpload> _pendingUploads = [];
  final Set<String> _cancelledPendingUploadIds = {};
  final _appSettingsService = AppSettingsService();
  AppSettings _appSettings = const AppSettings(
    notificationsEnabled: true,
    readReceiptsEnabled: true,
    typingIndicatorsEnabled: true,
    autoDownloadMedia: true,
    defaultChatFilter: 'all',
  );

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
    _mediaHandler = MediaHandler(
      matrixProvider: widget.matrixProvider,
      context: context,
    );
    _directChatService = DirectChatService(widget.matrixProvider.service);
    _initializeChat();
    _textCtrl.addListener(() {
      final has = _textCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);

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
    _loadPreviewType();
    _loadTimeline();
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
      if (_showMentionAutocomplete) {
        setState(() {
          _showMentionAutocomplete = false;
          _mentionQuery = '';
        });
      }
      return;
    }

    // Check if there's a space between @ and cursor
    final afterAt = beforeCursor.substring(lastAtIndex + 1);
    if (afterAt.contains(' ')) {
      // Space found, hide autocomplete
      if (_showMentionAutocomplete) {
        setState(() {
          _showMentionAutocomplete = false;
          _mentionQuery = '';
        });
      }
      return;
    }

    // Show autocomplete with query
    setState(() {
      _showMentionAutocomplete = true;
      _mentionQuery = afterAt;
    });
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

    // Listen to room updates for typing indicators
    _room!.onUpdate.stream.listen((_) {
      if (mounted) {
        final typingIndicators = _directChatService.getTypingUsers(_room!);
        final typingUserNames =
            typingIndicators.map((t) => t.displayName).toList();

        if (typingUserNames.join() != _typingUsers.join()) {
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

    setState(() {
      _showMentionAutocomplete = false;
      _mentionQuery = '';
    });
  }

  Future<void> _loadTimeline() async {
    if (_room == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final timeline = await widget.matrixProvider.service.getTimeline(_room!.id);
    if (mounted) {
      setState(() {
        _timeline = timeline;
        _loading = false;
      });
      _scrollToBottom();
      _markRoomAsRead();
      _loadPinnedMessages();
      _eventSub = widget.matrixProvider.service.onEvent.listen((update) {
        if (update.roomID == _room!.id && mounted) {
          setState(() {});
          _scrollToBottom();
          if (update.type == EventUpdateType.timeline) {
            _markRoomAsRead();
          }
          // Reload pinned messages if state changed
          if (update.type == EventUpdateType.state) {
            _loadPinnedMessages();
            _loadOwnRestriction();
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
    for (final eventId in pinnedEventIds) {
      try {
        final event = await _room!.getEventById(eventId);
        if (event != null) {
          events.add(event);
        }
      } catch (e) {
        debugPrint('[PinnedMessages] Failed to fetch event $eventId: $e');
      }
    }

    if (mounted) {
      setState(() => _pinnedEvents = events);
    }
  }

  void _showPinnedMessages() {
    showPinnedMessagesSheet(
      context: context,
      pinnedEvents: _pinnedEvents,
      canUnpin: _canPinMessages(),
      onUnpin: _togglePinMessage,
    );
  }

  void _preloadVideoThumbnails(Timeline timeline) {
    final videoEvents = timeline.events.where(
      (e) =>
          e.type == EventTypes.Message && e.messageType == MessageTypes.Video,
    );
    for (final event in videoEvents) {
      // Fire-and-forget: fills _mediaHandler cache in background
      _mediaHandler.loadVideoThumbnail(event).ignore();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _room == null) return;
    if (_isReadOnlyRestricted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are in read-only mode in this group'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _textCtrl.clear();
    setState(() => _hasText = false);

    // Send reply if replying to a message
    if (_replyToEvent != null) {
      await _room!.sendTextEvent(text, inReplyTo: _replyToEvent);
      setState(() => _replyToEvent = null);
    } else {
      await widget.matrixProvider.sendMessage(_room!.id, text);
    }

    _scrollToBottom();
  }

  Future<void> _startAudioRecording() async {
    if (_room == null || _uploading || _recording) return;
    if (kIsWeb) {
      _showSnackBar('Voice recording is not available in the web build yet.');
      return;
    }
    if (_isReadOnlyRestricted) {
      _showSnackBar('You are in read-only mode in this group');
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
          _recordingDuration =
              _recordingAccumulatedDuration + DateTime.now().difference(startedAt);
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
      });
    } catch (e) {
      _showSnackBar('Failed to start recording: $e');
    }
  }

  void _handleRecordingAmplitude(Amplitude amplitude) {
    if (!mounted || !_recording || _recordingPaused) return;

    final normalized = ((amplitude.current + 45) / 45).clamp(0.08, 1.0);
    final next = List<double>.from(_recordingWaveform)..add(normalized);
    if (next.length > 56) {
      next.removeRange(0, next.length - 56);
    }
    setState(() => _recordingWaveform = next);
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
    setState(() => _replyToEvent = event);
  }

  void _cancelReply() {
    setState(() => _replyToEvent = null);
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
    setState(() => _pendingUploads.removeWhere((upload) => upload.id == id));
  }

  void _cancelPendingUpload(String id) {
    _cancelledPendingUploadIds.add(id);
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
    setState(() {
      _pendingUploads[index].uploadedBytes = uploadedBytes;
      _pendingUploads[index].totalBytes = totalBytes;
    });
  }

  Future<void> _sendPhotoWithPending(
    String roomId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String caption,
  }) async {
    int? width;
    int? height;

    try {
      final imageSize = await _readImageSize(bytes);
      width = imageSize?.width.round();
      height = imageSize?.height.round();
    } catch (e) {
      debugPrint('[UploadPreview] Failed to read image size: $e');
    }

    final pendingId = _addPendingUpload(
      _PendingUpload(
        id: 'photo_${DateTime.now().microsecondsSinceEpoch}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isVideo: false,
        totalBytes: bytes.length,
        createdAt: DateTime.now(),
        width: width,
        height: height,
      ),
    );

    await _mediaHandler.sendPhotoBytes(
      roomId,
      _setUploading,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      caption: caption,
      onUploadProgress: (uploadedBytes, totalBytes) =>
          _updatePendingUploadProgress(pendingId, uploadedBytes, totalBytes),
    );
    _removePendingUpload(pendingId);
    _scrollToBottom();
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

  Future<void> _sendVideoWithPending(
    String roomId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String caption,
  }) async {
    Uint8List? thumbnailBytes;
    int? width;
    int? height;
    int? durationMs;

    try {
      final metadata = await _mediaHandler.readVideoPreviewMetadata(bytes);
      width = metadata?.width;
      height = metadata?.height;
      durationMs = metadata?.durationMs;
    } catch (e) {
      debugPrint('[UploadPreview] Failed to read video metadata: $e');
    }

    try {
      thumbnailBytes =
          await _mediaHandler.createVideoPreviewThumbnail(bytes, mimeType);
    } catch (e) {
      debugPrint('[UploadPreview] Failed to create video thumbnail: $e');
    }

    final pendingId = _addPendingUpload(
      _PendingUpload(
        id: 'video_${DateTime.now().microsecondsSinceEpoch}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isVideo: true,
        totalBytes: bytes.length,
        createdAt: DateTime.now(),
        thumbnailBytes: thumbnailBytes,
        width: width,
        height: height,
        durationMs: durationMs,
      ),
    );

    await _mediaHandler.sendVideoBytes(
      roomId,
      _setUploading,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      caption: caption,
      onUploadProgress: (uploadedBytes, totalBytes) =>
          _updatePendingUploadProgress(pendingId, uploadedBytes, totalBytes),
    );
    _removePendingUpload(pendingId);
    _scrollToBottom();
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
        totalBytes: bytes.length,
        createdAt: DateTime.now(),
        durationMs: durationMs,
      ),
    );

    _setUploading(true);
    try {
      await widget.matrixProvider.service.sendAudio(
        roomId: roomId,
        audioBytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        durationMs: durationMs,
        isVoiceMessage: isVoiceMessage,
        onUploadProgress: (uploadedBytes, totalBytes) =>
            _updatePendingUploadProgress(pendingId, uploadedBytes, totalBytes),
        isCancelled: () => _isPendingUploadCancelled(pendingId),
      );
    } finally {
      _removePendingUpload(pendingId);
      _cancelledPendingUploadIds.remove(pendingId);
      _setUploading(false);
    }
    _scrollToBottom();
  }

  Future<void> _sendFileWithPending(
    String roomId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final pendingId = _addPendingUpload(
      _PendingUpload(
        id: 'file_${DateTime.now().microsecondsSinceEpoch}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isVideo: false,
        isFile: true,
        totalBytes: bytes.length,
        createdAt: DateTime.now(),
      ),
    );

    _setUploading(true);
    try {
      await widget.matrixProvider.service.sendFileWithProgress(
        roomId: roomId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        onUploadProgress: (uploadedBytes, totalBytes) =>
            _updatePendingUploadProgress(pendingId, uploadedBytes, totalBytes),
        isCancelled: () => _isPendingUploadCancelled(pendingId),
      );
    } finally {
      _removePendingUpload(pendingId);
      _cancelledPendingUploadIds.remove(pendingId);
      _setUploading(false);
    }
    _scrollToBottom();
  }

  Future<void> _pickAndSendAudioWithPending() async {
    final room = _room;
    if (room == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;
    final durationMs = await _readAudioDurationMs(picked.path);

    try {
      await _sendAudioWithPending(
        room.id,
        bytes: bytes,
        fileName: picked.name,
        mimeType: lookupMimeType(picked.name) ?? 'audio/mpeg',
        durationMs: durationMs,
        isVoiceMessage: false,
      );
    } catch (e) {
      if (e is! MatrixUploadCancelledException) {
        _showSnackBar('Failed to send audio: $e');
      }
    }
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;

    try {
      await _sendFileWithPending(
        room.id,
        bytes: bytes,
        fileName: picked.name,
        mimeType: lookupMimeType(picked.name) ?? 'application/octet-stream',
      );
    } catch (e) {
      if (e is! MatrixUploadCancelledException) {
        _showSnackBar('Failed to send file: $e');
      }
    }
  }

  void _showAttachmentSheet() {
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

  Future<void> _openCameraForChat() async {
    final room = _room;
    if (room == null) return;

    final result = await Navigator.push<CameraCaptureResult>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (!mounted || result == null) return;

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

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif',
        'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv', 'm4v', '3gp',
      ],
      withData: true,
      allowMultiple: false,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

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

      final matrixFile = await event.downloadAndDecryptAttachment(
        downloadCallback: _mediaHandler.authenticatedDownload(),
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
          ),
        ),
      );
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPlayer.loading(
          videoFuture: event.downloadAndDecryptAttachment(
            downloadCallback: _mediaHandler.authenticatedDownload(),
          ),
          title: event.body,
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
        ),
      ),
    );
  }

  Future<void> _downloadAndOpenFile(Event event) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${event.body}...'),
          backgroundColor: kDarkerGrey,
          duration: const Duration(seconds: 2),
        ),
      );

      final matrixFile = await event.downloadAndDecryptAttachment(
        downloadCallback: _mediaHandler.authenticatedDownload(),
      );
      final bytes = matrixFile.bytes;

      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Downloaded file is empty'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await web_download.downloadFile(bytes, matrixFile.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kIsWeb
                ? 'Downloaded: ${matrixFile.name}'
                : 'Downloaded successfully'),
            backgroundColor: const Color(0xFF1A2A1A),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<MatrixFile> _downloadAttachment(Event event) {
    return event.downloadAndDecryptAttachment(
      downloadCallback: _mediaHandler.authenticatedDownload(),
    );
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
                (e.type == EventTypes.Message ||
                    e.type == EventTypes.Encrypted))
            .toList()
            .reversed
            .toList() ??
        [];
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
    final canReply = event.type == EventTypes.Message;
    final canForward = _canForwardMessage(event);
    final canCopy = _copyableMessageText(event) != null;
    final canDownload = _canDownloadAttachment(event);
    final canShowMenu =
        canReply ||
        canCopy ||
        canForward ||
        canDownload ||
        canEdit ||
        canDelete ||
        _canPinMessages();

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
                child: isImage || isVideo
                    ? MediaMessageBubble(
                        event: displayEvent,
                        isMe: isMe,
                        senderName: senderName,
                        time: time,
                        isImage: isImage,
                        loadImageBytes: _mediaHandler.loadImageBytes,
                        loadVideoThumbnail: _mediaHandler.loadVideoThumbnail,
                        playVideo: _openVideoPlayer,
                        openFullscreenImage: _openFullscreenImage,
                        buildMessageStatus: (_) => _buildMessageStatus(event),
                        isEdited: isEdited,
                      )
                    : TextOrFileMessageBubble(
                        event: displayEvent,
                        isMe: isMe,
                        senderName: senderName,
                        time: time,
                        isAudio: isAudio,
                        isFile: isFile,
                        downloadAndOpenFile: _downloadAndOpenFile,
                        downloadAttachment: _downloadAttachment,
                        buildMessageStatus: (_) => _buildMessageStatus(event),
                        loadImageBytes: _mediaHandler.loadImageBytes,
                        loadVideoThumbnail: _mediaHandler.loadVideoThumbnail,
                        isEdited: isEdited,
                        onReplyTap: _scrollToAndHighlightMessage,
                      ),
              ),
            ),
          ),
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
                )
              : upload.isFile
                  ? _PendingFileUploadBubble(
                      upload: upload,
                      onCancel: () => _cancelPendingUpload(upload.id),
                    )
                  : _PendingMediaUploadBubble(upload: upload),
        ),
      ),
    );
  }

  bool _canDeleteMessage(Event event) {
    if (_room == null) return false;

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

  bool _canEditMessage(Event event) {
    if (_room == null) return false;

    // Only the sender can edit their own messages
    final isMyMessage = event.senderId == _myUserId;

    // Can only edit text messages
    final isTextMessage = event.messageType == MessageTypes.Text ||
        event.messageType == MessageTypes.Notice ||
        event.messageType == MessageTypes.Emote;

    return isMyMessage && isTextMessage;
  }

  bool _canForwardMessage(Event event) {
    if (event.redacted) return false;
    if (event.type != EventTypes.Message && event.type != EventTypes.Sticker) {
      return false;
    }
    return event.content['msgtype'] is String;
  }

  bool _canDownloadAttachment(Event event) {
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
    await _downloadAndOpenFile(_displayEventFor(event));
  }

  Future<void> _shareMessageAttachment(Event event) async {
    try {
      final displayEvent = _displayEventFor(event);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preparing ${displayEvent.body}...'),
          backgroundColor: kDarkerGrey,
          duration: const Duration(seconds: 2),
        ),
      );

      final matrixFile = await displayEvent.downloadAndDecryptAttachment(
        downloadCallback: _mediaHandler.authenticatedDownload(),
      );

      await native_share.shareFile(
        matrixFile.bytes,
        matrixFile.name,
        mimeType: matrixFile.mimeType,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
      !_isReadOnlyRestricted;

  int _ownPowerLevel() {
    if (_room == null) return 0;
    for (final user in _room!.getParticipants()) {
      if (user.id == _myUserId) return user.powerLevel;
    }
    return _room!.ownPowerLevel;
  }

  void _showMessageOptions(Event event) {
    final isPinned = _pinnedEvents.any((e) => e.eventId == event.eventId);
    final canEdit = _canEditMessage(event);
    final canDelete = _canDeleteMessage(event);
    final canForward = _canForwardMessage(event);
    final canCopy = _copyableMessageText(event) != null;
    final canDownload = _canDownloadAttachment(event);

    showModalBottomSheet(
      context: context,
      backgroundColor: kDarkerGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply, color: kLimeGreen),
                title: Text(
                  'Reply',
                  style: GoogleFonts.inter(color: kWhite),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _setReplyTo(event);
                },
              ),
              if (canCopy)
                ListTile(
                  leading: const Icon(Icons.copy, color: kLimeGreen),
                  title: Text(
                    'Copy',
                    style: GoogleFonts.inter(color: kWhite),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyMessageText(event);
                  },
                ),
              if (_isDirectRoom)
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined,
                      color: kLimeGreen),
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
                  leading: const Icon(Icons.forward, color: kLimeGreen),
                  title: Text(
                    'Forward',
                    style: GoogleFonts.inter(color: kWhite),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _forwardMessage(event);
                  },
                ),
              if (canDownload)
                ListTile(
                  leading:
                      const Icon(Icons.download_outlined, color: kLimeGreen),
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
                  leading: const Icon(Icons.share_outlined, color: kLimeGreen),
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
                  leading: const Icon(Icons.edit, color: kLimeGreen),
                  title: Text(
                    'Edit Message',
                    style: GoogleFonts.inter(color: kWhite),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editMessage(event);
                  },
                ),
              if (_canPinMessages())
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                    color: kLimeGreen,
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
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
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
    );
  }

  Future<void> _forwardMessage(Event event) async {
    final room = _room;
    if (room == null) return;

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
          backgroundColor: const Color(0xFF1A2A1A),
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

  void _showReactionPicker(Event event) {
    ReactionPicker.show(context, (emoji) async {
      try {
        await _directChatService.addReaction(_room!.id, event.eventId, emoji);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reaction added'),
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
    });
  }

  Future<void> _editMessage(Event event) async {
    final currentText = _displayEventFor(event).calcUnlocalizedBody(
      hideReply: true,
      hideEdit: true,
    );
    final controller = TextEditingController(text: currentText);

    final newText = await showDialog<String>(
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
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('Save', style: GoogleFonts.inter(color: kLimeGreen)),
          ),
        ],
      ),
    );

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
      await event.redactEvent();
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
    // For direct chats, use enhanced read receipts
    if (_isDirectRoom) {
      // Determine status based on event state
      // For now, we'll use a simplified version
      // In a real implementation, you'd check actual read receipts from the Matrix SDK

      final isRead = _directChatService.isMessageRead(event, _room!);

      if (isRead) {
        return const ReadReceipt(status: ReadReceiptStatus.read);
      } else {
        // Check if delivered (simplified - in reality you'd check delivery receipts)
        return const ReadReceipt(status: ReadReceiptStatus.delivered);
      }
    }

    // For groups/channels, use simple check mark
    return Icon(
      Icons.done,
      color: kLimeGreen.withValues(alpha: 0.6),
      size: 12,
    );
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

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text(
          'Delete Group/Channel?',
          style: GoogleFonts.inter(color: kWhite),
        ),
        content: Text(
          'This will permanently delete the group/channel for all members. This action cannot be undone.',
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
                  'Deleting group...',
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
          const SnackBar(
            content: Text('Group/Channel deleted successfully'),
            backgroundColor: kLimeGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete group: $e'),
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
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _eventSub?.cancel();
    _typingTimer?.cancel();
    _highlightTimer?.cancel();
    _mediaHandler.clearCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _visibleMessages();

    return Scaffold(
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
                widget.previewChannel!.name ?? widget.previewChannel!.roomId,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
      body: Stack(
        children: [
          const Positioned.fill(child: ChatSpaceBackground()),
          Column(
            children: [
              // Pinned Messages Banner
              if (_pinnedEvents.isNotEmpty)
                PinnedMessagesBanner(
                  pinnedEvents: _pinnedEvents,
                  onTap: _showPinnedMessages,
                ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kLimeGreen),
                      )
                    : messages.isEmpty && _pendingUploads.isEmpty
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
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 8,
                            ),
                            itemCount: messages.length + _pendingUploads.length,
                            itemBuilder: (_, i) {
                              if (i < messages.length) {
                                return _buildBubble(messages[i]);
                              }
                              return _buildPendingUploadBubble(
                                _pendingUploads[i - messages.length],
                              );
                            },
                          ),
              ),
              // Reply Preview
              if (_replyToEvent != null)
                ReplyPreview(
                  replyToEvent: _replyToEvent!,
                  onCancel: _cancelReply,
                ),
              // Mention Autocomplete
              if (_showMentionAutocomplete && _groupMembers.isNotEmpty)
                MentionAutocomplete(
                  members: _groupMembers,
                  query: _mentionQuery,
                  onMemberSelected: _insertMention,
                ),
              // Typing Indicator (Direct Chats Only)
              if (_isDirectRoom && _typingUsers.isNotEmpty)
                TypingIndicator(userName: _typingUsers.first),
              if (_room == null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _joinPreviewChannel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kLimeGreen,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _getJoinButtonText(),
                        style: GoogleFonts.inter(
                          color: kBlack,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                )
              else if (_room!.canSendEvent('m.room.message'))
                ChatInputBar(
                  textController: _textCtrl,
                  hasText: _hasText,
                  uploading: _uploading,
                  recording: _recording,
                  recordingPaused: _recordingPaused,
                  recordingDuration: _recordingDuration,
                  recordingWaveform: _recordingWaveform,
                  enabled: _canSendMessages,
                  disabledText: _isReadOnlyRestricted
                      ? 'Read-only mode'
                      : 'You cannot send messages',
                  onSend: _sendMessage,
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
        ],
      ),
    );
  }
}

class _PendingUpload {
  final String id;
  final Uint8List bytes;
  final Uint8List? thumbnailBytes;
  final String fileName;
  final String mimeType;
  final bool isVideo;
  final bool isAudio;
  final bool isFile;
  int totalBytes;
  int uploadedBytes = 0;
  final DateTime createdAt;
  final int? width;
  final int? height;
  final int? durationMs;

  _PendingUpload({
    required this.id,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.isVideo,
    this.isAudio = false,
    this.isFile = false,
    required this.totalBytes,
    required this.createdAt,
    this.thumbnailBytes,
    this.width,
    this.height,
    this.durationMs,
  });
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
  final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

class _PendingAudioUploadBubble extends StatelessWidget {
  final _PendingUpload upload;
  final VoidCallback onCancel;

  const _PendingAudioUploadBubble({
    required this.upload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _uploadProgress(upload);

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
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 330),
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
                      _PendingCancelProgressButton(
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

  const _PendingFileUploadBubble({
    required this.upload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _uploadProgress(upload);

    return Container(
      width: 280,
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
              _PendingCancelProgressButton(
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
                          'File',
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

  const _PendingCancelProgressButton({
    required this.progress,
    required this.onCancel,
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
              decoration: const BoxDecoration(
                color: kLimeGreen,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: kBlack,
                backgroundColor: kBlack.withValues(alpha: 0.32),
              ),
            ),
            const Icon(
              Icons.close_rounded,
              color: kBlack,
              size: 26,
            ),
          ],
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

  const _PendingMediaUploadBubble({required this.upload});

  @override
  Widget build(BuildContext context) {
    final size = upload.isVideo
        ? _displayVideoSizeForRatio(_aspectRatio)
        : _displayImageSizeForRatio(_aspectRatio);

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

  Size _displayImageSizeForRatio(double aspectRatio) {
    return _displaySizeForRatio(
      aspectRatio,
      maxWidth: 292,
      maxHeight: 336,
    );
  }

  Size _displayVideoSizeForRatio(double aspectRatio) {
    return _displaySizeForRatio(
      aspectRatio,
      maxWidth: 292,
      maxHeight: 360,
    );
  }

  Size _displaySizeForRatio(
    double aspectRatio, {
    required double maxWidth,
    required double maxHeight,
  }) {
    const minReadableHeight = 96.0;

    final ratio = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 16 / 9;

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
      width = (height * ratio).clamp(140.0, maxWidth);
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
