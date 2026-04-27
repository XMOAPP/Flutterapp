import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../theme.dart';
import '../providers/matrix_provider.dart';
import '../services/matrix_service.dart';

/// Real-time Matrix chat screen for a given Room.
/// Mirrors the dark aesthetic of ChatScreen but is backed by live Matrix data.
class MatrixChatScreen extends StatefulWidget {
  final Room room;
  final MatrixProvider matrixProvider;

  const MatrixChatScreen({
    super.key,
    required this.room,
    required this.matrixProvider,
  });

  @override
  State<MatrixChatScreen> createState() => _MatrixChatScreenState();
}

class _MatrixChatScreenState extends State<MatrixChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timeline? _timeline;
  bool _loading = true;
  bool _hasText = false;
  StreamSubscription<EventUpdate>? _eventSub;

  Room get _room => widget.room;
  String get _myUserId => widget.matrixProvider.userId ?? '';

  @override
  void initState() {
    super.initState();
    _loadTimeline();
    _textCtrl.addListener(() {
      final has = _textCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  Future<void> _loadTimeline() async {
    final timeline = await widget.matrixProvider.service.getTimeline(_room.id);
    if (mounted) {
      setState(() {
        _timeline = timeline;
        _loading = false;
      });
      _scrollToBottom();
      // Listen for new events in real-time
      _eventSub = widget.matrixProvider.service.onEvent.listen((update) {
        if (update.roomID == _room.id && mounted) {
          setState(() {});
          _scrollToBottom();
        }
      });
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
    if (text.isEmpty) return;
    _textCtrl.clear();
    setState(() => _hasText = false);
    await widget.matrixProvider.sendMessage(_room.id, text);
    _scrollToBottom();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _timeline?.events
            .where((e) => e.type == EventTypes.Message)
            .toList()
            .reversed
            .toList() ??
        [];

    return Scaffold(
      backgroundColor: kBlack,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kBlue))
                : messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline,
                                color: kMediumGrey, size: 48),
                            const SizedBox(height: 12),
                            Text('No messages yet. Say hello!',
                                style: GoogleFonts.inter(
                                    color: kLightGrey, fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => _buildBubble(messages[i]),
                      ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    final rawName = _room.getLocalizedDisplayname();
    final memberCount = _room.summary.mJoinedMemberCount ?? 0;
    final isDirect = memberCount == 2;
    
    // For direct chats, clean up the name (remove "Group with" prefix)
    String displayName = rawName;
    if (isDirect) {
      // Remove "Group with " prefix if present
      if (displayName.toLowerCase().startsWith('group with ')) {
        displayName = displayName.substring(11); // Remove "Group with "
      }
      // Remove "Direct Room with " prefix if present
      if (displayName.toLowerCase().startsWith('direct room with ')) {
        displayName = displayName.substring(17); // Remove "Direct Room with "
      }
    }
    final name = MatrixService.cleanName(displayName);

    return AppBar(
      backgroundColor: kBlack,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: kWhite),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kBlue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.inter(
                    color: kBlack, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                      color: kWhite, fontSize: 15, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                // Only show subtitle for groups (3+ members)
                if (!isDirect)
                  Text(
                    '$memberCount members',
                    style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: kWhite, size: 22),
          color: kDarkerGrey,
          onSelected: (value) async {
            if (value == 'leave') {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kDarkerGrey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    'Delete Chat?',
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  content: Text(
                    'Are you sure you want to delete this chat? This action cannot be undone.',
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
                        style: GoogleFonts.inter(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              
              if (confirm == true && mounted) {
                try {
                  await _room.leave();
                  if (mounted) {
                    Navigator.pop(context);
                  }
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
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'leave',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Delete Chat',
                    style: GoogleFonts.inter(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBubble(Event event) {
    final isMe = event.senderId == _myUserId;
    final body = event.body;
    final time = _formatTime(event.originServerTs);
    final senderName = MatrixService.cleanName(event.senderId);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? kBlue : const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMe ? 18 : 4),
              topRight: const Radius.circular(18),
              bottomLeft: const Radius.circular(18),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    senderName,
                    style: GoogleFonts.inter(
                        color: kBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              Text(
                body,
                style: GoogleFonts.inter(
                  color: isMe ? kBlack : kWhite,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  time,
                  style: GoogleFonts.inter(
                    color:
                        isMe ? kBlack.withValues(alpha: 0.55) : kLightGrey,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: kDarkerGrey,
        border: Border(top: BorderSide(color: kDarkGrey, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: kDarkGrey,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_emotions_outlined,
                        color: kLightGrey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        style:
                            GoogleFonts.inter(color: kWhite, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle:
                              GoogleFonts.inter(color: kLightGrey, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: _hasText
                  ? GestureDetector(
                      key: const ValueKey('send'),
                      onTap: _sendMessage,
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(left: 8),
                        decoration: const BoxDecoration(
                          color: kBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send_rounded,
                            color: kBlack, size: 20),
                      ),
                    )
                  : const SizedBox(width: 8),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
