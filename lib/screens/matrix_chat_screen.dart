import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
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
import 'matrix_chat/attachment_sheet.dart';
import 'matrix_chat/chat_app_bar.dart';
import 'matrix_chat/chat_input_bar.dart';
import 'matrix_chat/media_handler.dart';
import 'matrix_chat/message_widgets.dart';
import 'matrix_chat/pinned_messages_sheet.dart';

// Web download helper
import 'web_download_stub.dart' if (dart.library.html) 'web_download.dart'
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

  void _showAttachmentSheet() {
    showChatAttachmentSheet(
      context: context,
      onGallery: () {
        if (_room != null) {
          _mediaHandler
              .pickAndSendGallery(_room!.id, _setUploading)
              .then((_) => _scrollToBottom());
        }
      },
      onDocuments: () {
        if (_room != null) {
          _mediaHandler
              .pickAndSendFile(_room!.id, _setUploading)
              .then((_) => _scrollToBottom());
        }
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

      web_download.downloadFile(bytes, matrixFile.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: ${matrixFile.name}'),
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

  Widget _buildBubble(Event event) {
    final isMe = event.senderId == _myUserId;
    final time = _formatTime(event.originServerTs);
    final senderName = MatrixService.cleanName(event.senderId);

    final msgtype = event.messageType;
    final isImage = msgtype == MessageTypes.Image;
    final isVideo = msgtype == MessageTypes.Video;
    final isAudio = msgtype == MessageTypes.Audio;
    final isFile = msgtype == MessageTypes.File;

    // Determine if user can perform any actions on this message
    final canEdit = _canEditMessage(event);
    final canDelete = _canDeleteMessage(event);
    final canReply = event.type == EventTypes.Message;
    final canShowMenu = canReply || canEdit || canDelete || _canPinMessages();

    return GestureDetector(
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
                  event: event,
                  isMe: isMe,
                  senderName: senderName,
                  time: time,
                  isImage: isImage,
                  loadImageBytes: _mediaHandler.loadImageBytes,
                  loadVideoThumbnail: _mediaHandler.loadVideoThumbnail,
                  playVideo: _playVideo,
                  openFullscreenImage: _openFullscreenImage,
                  buildMessageStatus: _buildMessageStatus,
                )
              : TextOrFileMessageBubble(
                  event: event,
                  isMe: isMe,
                  senderName: senderName,
                  time: time,
                  isAudio: isAudio,
                  isFile: isFile,
                  downloadAndOpenFile: _downloadAndOpenFile,
                  buildMessageStatus: _buildMessageStatus,
                ),
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
    final controller = TextEditingController(text: event.body);

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

    if (newText == null || newText.isEmpty || newText == event.body) return;

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
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _eventSub?.cancel();
    _typingTimer?.cancel();
    _mediaHandler.clearCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _timeline?.events
            .where((e) =>
                e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
            .toList()
            .reversed
            .toList() ??
        [];

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
      body: Column(
        children: [
          if (_uploading)
            const LinearProgressIndicator(
              color: kLimeGreen,
              backgroundColor: kDarkGrey,
              minHeight: 2,
            ),
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
                : messages.isEmpty
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
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => _buildBubble(messages[i]),
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
              enabled: _canSendMessages,
              disabledText: _isReadOnlyRestricted
                  ? 'Read-only mode'
                  : 'You cannot send messages',
              onSend: _sendMessage,
              onShowAttachmentSheet: _showAttachmentSheet,
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
    );
  }
}
