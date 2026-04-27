import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/data_models.dart';

class ChatScreen extends StatefulWidget {
  final ChatModel chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<MessageModel> _messages;
  bool _isPlayingAudio = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _messages = List.from(MockData.getMessages(widget.chat.id));
    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final newMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text,
      isOutgoing: true,
      time: TimeOfDay.now().format(context),
      type: MessageType.text,
    );

    setState(() {
      _messages.add(newMessage);
      _textController.clear();
      _hasText = false;
    });

    _scrollToBottom();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _MessageBubble(
                  message: _messages[index],
                  isPlaying: _isPlayingAudio,
                  onAudioTap: () {
                    setState(() => _isPlayingAudio = !_isPlayingAudio);
                  },
                );
              },
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    final chat = widget.chat;
    final avatarColor = _parseColor(chat.avatarColor);

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
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: chat.imageUrl != null ? null : avatarColor,
                  shape: BoxShape.circle,
                  image: chat.imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(chat.imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: chat.imageUrl == null
                    ? Center(
                        child: Text(
                          chat.avatarText.length > 2
                              ? chat.avatarText.substring(0, 2)
                              : chat.avatarText,
                          style: GoogleFonts.inter(
                            color: kWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              ),
              if (chat.isOnline)
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: kBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: kBlack, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chat.name,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                chat.isOnline
                    ? 'online'
                    : chat.isGroup
                        ? '${_groupMemberCount(chat.id)} members'
                        : 'last seen recently',
                style: GoogleFonts.inter(
                  color: chat.isOnline ? kBlue : kLightGrey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.phone_outlined, color: kWhite, size: 22),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.videocam_outlined, color: kWhite, size: 22),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.search, color: kWhite, size: 22),
          onPressed: () {},
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: kWhite, size: 22),
          color: kDarkGrey,
          onSelected: (value) {},
          itemBuilder: (context) => [
            _menuItem('View profile', Icons.person_outline),
            _menuItem('Mute notifications', Icons.notifications_off_outlined),
            _menuItem('Search', Icons.search),
            _menuItem('Clear history', Icons.delete_sweep_outlined),
            _menuItem('Delete chat', Icons.delete_outline, isRed: true),
          ],
        ),
      ],
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null) return kMediumGrey;
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  String _groupMemberCount(String id) {
    const counts = {'1': '12', '2': '48', '7': '8', '9': '6'};
    return counts[id] ?? '10';
  }

  PopupMenuItem<String> _menuItem(String label, IconData icon,
      {bool isRed = false}) {
    return PopupMenuItem<String>(
      value: label,
      child: Row(
        children: [
          Icon(icon, color: isRed ? Colors.red[400] : kWhite, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isRed ? Colors.red[400] : kWhite,
              fontSize: 14,
            ),
          ),
        ],
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
            IconButton(
              icon: const Icon(Icons.attach_file, color: kLightGrey, size: 22),
              onPressed: () {},
            ),
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
                        controller: _textController,
                        style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: GoogleFonts.inter(
                              color: kLightGrey, fontSize: 14),
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
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: child,
              ),
              child: _hasText
                  ? GestureDetector(
                      key: const ValueKey('send'),
                      onTap: _sendMessage,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: kBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: kBlack,
                          size: 20,
                        ),
                      ),
                    )
                  : IconButton(
                      key: const ValueKey('mic'),
                      icon: const Icon(Icons.mic_none,
                          color: kLightGrey, size: 24),
                      onPressed: () {},
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isPlaying;
  final VoidCallback onAudioTap;

  const _MessageBubble({
    required this.message,
    required this.isPlaying,
    required this.onAudioTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;

    Widget content;
    if (message.type == MessageType.image) {
      content = _ImageBubble(imageUrl: message.imageUrl!, time: message.time);
    } else if (message.type == MessageType.audio) {
      content = _AudioBubble(
        duration: message.audioDuration!,
        time: message.time,
        isPlaying: isPlaying,
        onPlay: onAudioTap,
      );
    } else {
      content = _TextBubble(
        text: message.content,
        isOutgoing: isOutgoing,
        time: message.time,
      );
    }

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isOutgoing ? 48 : 0,
          right: isOutgoing ? 0 : 48,
        ),
        child: content,
      ),
    );
  }
}

class _TextBubble extends StatelessWidget {
  final String text;
  final bool isOutgoing;
  final String time;

  const _TextBubble({
    required this.text,
    required this.isOutgoing,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isOutgoing ? kBlue : const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isOutgoing ? 18 : 4),
          topRight: const Radius.circular(18),
          bottomLeft: const Radius.circular(18),
          bottomRight: Radius.circular(isOutgoing ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            text,
            style: GoogleFonts.inter(
              color: isOutgoing ? kBlack : kWhite,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            time,
            style: GoogleFonts.inter(
              color: isOutgoing ? kBlack.withValues(alpha: 0.55) : kLightGrey,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  final String imageUrl;
  final String time;

  const _ImageBubble({required this.imageUrl, required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF2C2C2E),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: 240,
            height: 180,
            errorBuilder: (_, __, ___) => Container(
              width: 240,
              height: 180,
              color: kMediumGrey,
              child: const Icon(Icons.image, color: kLightGrey, size: 40),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 10,
            child: Text(
              time,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioBubble extends StatelessWidget {
  final String duration;
  final String time;
  final bool isPlaying;
  final VoidCallback onPlay;

  const _AudioBubble({
    required this.duration,
    required this.time,
    required this.isPlaying,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF2C2C2E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onPlay,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: kBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: kBlack,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(28, (index) {
                    const heights = [
                      12.0,
                      18.0,
                      10.0,
                      22.0,
                      16.0,
                      8.0,
                      20.0,
                      14.0,
                      24.0,
                      10.0,
                      18.0,
                      12.0,
                      20.0,
                      8.0,
                      16.0,
                      22.0,
                      10.0,
                      18.0,
                      14.0,
                      20.0,
                      12.0,
                      8.0,
                      24.0,
                      16.0,
                      10.0,
                      18.0,
                      12.0,
                      20.0,
                    ];
                    final pct = index / 28;
                    final played = isPlaying && pct < 0.35;
                    return Container(
                      width: 3,
                      height: heights[index % heights.length],
                      margin: const EdgeInsets.symmetric(horizontal: 0.8),
                      decoration: BoxDecoration(
                        color: played ? kBlue : kLightGrey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                  duration,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
