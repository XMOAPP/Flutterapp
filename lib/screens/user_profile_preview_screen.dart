import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../theme.dart';
import '../utils/matrix_identity.dart';
import '../widgets/story/story_avatar.dart';
import 'matrix_chat_screen.dart';

class UserProfilePreviewScreen extends StatefulWidget {
  const UserProfilePreviewScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<UserProfilePreviewScreen> createState() =>
      _UserProfilePreviewScreenState();
}

class _UserProfilePreviewScreenState extends State<UserProfilePreviewScreen> {
  bool _startingChat = false;
  String? _error;

  Future<void> _openChat() async {
    final userId = widget.profile.userId;
    if (userId.isEmpty || _startingChat) return;

    setState(() {
      _startingChat = true;
      _error = null;
    });

    final provider = context.read<MatrixProvider>();
    final existingRoom = provider.findExistingDirectRoom(userId);
    if (existingRoom != null) {
      _replaceWithChat(existingRoom, provider);
      return;
    }

    final roomId = await provider.startDirectChat(userId);
    if (!mounted) return;
    if (roomId == null) {
      setState(() {
        _startingChat = false;
        _error = provider.error ?? 'Could not start chat.';
      });
      return;
    }

    final room = await _waitForRoom(provider, roomId);
    if (!mounted) return;
    if (room == null) {
      setState(() {
        _startingChat = false;
        _error = 'Chat is being created. Please try again shortly.';
      });
      return;
    }

    _replaceWithChat(room, provider);
  }

  Future<Room?> _waitForRoom(MatrixProvider provider, String roomId) async {
    for (final delay in const [
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 600),
      Duration(milliseconds: 1000),
    ]) {
      if (delay != Duration.zero) await Future.delayed(delay);
      final room = provider.service.getRoomById(roomId);
      if (room != null) return room;
    }
    provider.refreshRooms();
    return provider.service.getRoomById(roomId);
  }

  void _replaceWithChat(Room room, MatrixProvider provider) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MatrixChatScreen(room: room, matrixProvider: provider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanUsername = MatrixIdentity.localpart(widget.profile.userId);
    final title = MatrixIdentity.displayName(
      userId: widget.profile.userId,
      candidate: widget.profile.displayName,
    );
    final subtitle = MatrixIdentity.usernameLabel(widget.profile.userId);

    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: Column(
                children: [
                  StoryAvatar(
                    userName: cleanUsername.isEmpty ? title : cleanUsername,
                    avatarUrl: widget.profile.avatarUrl?.toString(),
                    size: 104,
                    backgroundColor: const Color(0xFF2C2C2E),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    width: 240,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _startingChat ? null : _openChat,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kWhite,
                        foregroundColor: kBlack,
                        disabledBackgroundColor: kMediumGrey,
                        disabledForegroundColor: kLightGrey,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: _startingChat
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kLightGrey,
                              ),
                            )
                          : Text(
                              'Message',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
