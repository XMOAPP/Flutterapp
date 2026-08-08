import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../models/story_models.dart';
import '../../providers/story_provider.dart';
import '../../providers/matrix_provider.dart';
import '../../widgets/direct_chat/message_reactions.dart';
import '../../widgets/story/story_avatar.dart';
import '../../widgets/story/story_video_player.dart';
import 'story_creator_screen.dart';
import 'story_viewers_screen.dart';

/// Full-screen story viewer with swipe navigation
class StoryViewerScreen extends StatefulWidget {
  final int initialUserIndex; // -1 for my story
  final List<String> allUserStories; // List of user IDs with stories
  final String? initialStoryId;

  const StoryViewerScreen({
    super.key,
    required this.initialUserIndex,
    required this.allUserStories,
    this.initialStoryId,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  int _currentUserIndex = 0;
  int _currentStoryIndex = 0;
  List<Story> _currentUserStories = [];

  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  Timer? _progressTimer;
  final ValueNotifier<double> _progress = ValueNotifier<double>(0.0);
  bool _isPaused = false;
  String? _activeVideoStoryId;
  bool _sendingStoryReply = false;

  @override
  void initState() {
    super.initState();
    _currentUserIndex = widget.initialUserIndex;
    _replyFocusNode.addListener(_handleReplyFocusChanged);
    _loadCurrentUserStories();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _progress.dispose();
    _replyFocusNode.removeListener(_handleReplyFocusChanged);
    _replyFocusNode.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _handleReplyFocusChanged() {
    if (!mounted) return;
    if (_replyFocusNode.hasFocus) {
      _pauseStory();
    } else {
      _resumeStory();
    }
  }

  Future<void> _loadCurrentUserStories() async {
    final storyProvider = context.read<StoryProvider>();

    if (_currentUserIndex == -1) {
      // My stories
      setState(() {
        _currentUserStories = storyProvider.myStories
            .where((s) => !s.isExpired)
            .toList();
        _applyInitialStoryIndex();
      });
    } else if (_currentUserIndex >= 0 &&
        _currentUserIndex < widget.allUserStories.length) {
      // Contact stories
      final userId = widget.allUserStories[_currentUserIndex];
      final userStories = storyProvider.contactStories.firstWhere(
        (us) => us.userId == userId,
        orElse: () => UserStories(userId: userId, userName: '', stories: []),
      );
      setState(() {
        _currentUserStories = userStories.activeStories;
        _applyInitialStoryIndex();
      });
    }

    if (_currentUserStories.isNotEmpty) {
      _startStoryProgress();
      _markCurrentStoryAsViewed();
    }
  }

  void _startStoryProgress() {
    _progressTimer?.cancel();
    _progress.value = 0.0;
    _activeVideoStoryId = null;

    if (_currentStoryIndex >= _currentUserStories.length) return;

    final currentStory = _currentUserStories[_currentStoryIndex];
    if (_isVideoStory(currentStory)) {
      _activeVideoStoryId = currentStory.id;
      setState(() {});
      return;
    }

    const duration = Duration(seconds: 5); // 5 seconds per story
    const interval = Duration(milliseconds: 50);
    final increment = interval.inMilliseconds / duration.inMilliseconds;

    _progressTimer = Timer.periodic(interval, (timer) {
      if (_isPaused || !mounted) return;

      final nextProgress = _progress.value + increment;
      if (nextProgress >= 1.0) {
        _nextStory();
      } else {
        _progress.value = nextProgress;
      }
    });
  }

  void _pauseStory() {
    setState(() => _isPaused = true);
  }

  void _resumeStory() {
    setState(() => _isPaused = false);
  }

  void _nextStory() {
    if (_currentStoryIndex < _currentUserStories.length - 1) {
      // Next story from same user
      _resetReplyStateForStoryTransition();
      setState(() {
        _currentStoryIndex++;
        _progress.value = 0.0;
      });
      _markCurrentStoryAsViewed();
      _startStoryProgress();
    } else {
      // Next user's stories
      _nextUser();
    }
  }

  void _previousStory() {
    if (_currentStoryIndex > 0) {
      // Previous story from same user
      _resetReplyStateForStoryTransition();
      setState(() {
        _currentStoryIndex--;
        _progress.value = 0.0;
      });
      _startStoryProgress();
    } else {
      // Previous user's stories
      _previousUser();
    }
  }

  void _nextUser() {
    if (_currentUserIndex < widget.allUserStories.length - 1) {
      _resetReplyStateForStoryTransition();
      setState(() {
        _currentUserIndex++;
        _currentStoryIndex = 0;
        _progress.value = 0.0;
      });
      _loadCurrentUserStories();
    } else {
      // End of stories
      _closeViewer();
    }
  }

  void _previousUser() {
    if (_currentUserIndex > 0) {
      _resetReplyStateForStoryTransition();
      setState(() {
        _currentUserIndex--;
        _currentStoryIndex = 0;
        _progress.value = 0.0;
      });
      _loadCurrentUserStories();
    } else {
      _closeViewer();
    }
  }

  void _resetReplyStateForStoryTransition() {
    _replyController.clear();
    _replyFocusNode.unfocus();
  }

  bool _isOwnStory(Story story) {
    final currentUserId = context.read<MatrixProvider>().userId;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      return story.userId.trim().toLowerCase() ==
          currentUserId.trim().toLowerCase();
    }
    return _currentUserIndex == -1;
  }

  void _closeViewer() {
    _progressTimer?.cancel();
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }

  Future<void> _markCurrentStoryAsViewed() async {
    if (_currentStoryIndex < _currentUserStories.length) {
      final story = _currentUserStories[_currentStoryIndex];
      if (_isOwnStory(story)) return;
      final storyProvider = context.read<StoryProvider>();
      await storyProvider.markStoryAsViewed(story.userId, story.id);
    }
  }

  Future<void> _deleteStory() async {
    if (_currentStoryIndex >= _currentUserStories.length) return;

    final story = _currentUserStories[_currentStoryIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Delete Story?', style: GoogleFonts.inter(color: kWhite)),
        content: Text(
          'This story will be deleted permanently.',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final storyProvider = context.read<StoryProvider>();
      final success = await storyProvider.deleteStory(story.id);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Story deleted'),
            backgroundColor: kLimeGreen,
            duration: Duration(seconds: 2),
          ),
        );

        _progressTimer?.cancel();

        var shouldClose = false;
        setState(() {
          _currentUserStories.removeAt(_currentStoryIndex);
          if (_currentUserStories.isEmpty) {
            shouldClose = true;
          } else if (_currentStoryIndex >= _currentUserStories.length) {
            _currentStoryIndex = _currentUserStories.length - 1;
          }
        });

        if (shouldClose) {
          _closeViewer();
        } else {
          _startStoryProgress();
        }
      }
    }
  }

  Future<void> _viewStoryViewers() async {
    if (_currentStoryIndex >= _currentUserStories.length) return;

    final story = _currentUserStories[_currentStoryIndex];
    _pauseStory();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => StoryViewersSheet(storyId: story.id),
    );
    if (mounted) _resumeStory();
  }

  void _addStory() {
    _progressTimer?.cancel();
    setState(() => _isPaused = true);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StoryCreatorScreen()),
    ).then((_) {
      if (!mounted) return;
      setState(() => _isPaused = false);
      _loadCurrentUserStories();
    });
  }

  Future<void> _sendStoryReply(Story story) async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sendingStoryReply) return;

    await _sendStoryDirectMessage(story, text, successMessage: 'Reply sent');
  }

  void _applyInitialStoryIndex() {
    final initialStoryId = widget.initialStoryId;
    if (initialStoryId == null || initialStoryId.isEmpty) return;
    final index = _currentUserStories.indexWhere(
      (story) => story.id == initialStoryId,
    );
    if (index != -1) _currentStoryIndex = index;
  }

  Future<void> _sendStoryDirectMessage(
    Story story,
    String body, {
    required String successMessage,
  }) async {
    if (story.userId.isEmpty ||
        _isOwnStory(story) ||
        _currentStoryIndex >= _currentUserStories.length ||
        _currentUserStories[_currentStoryIndex].id != story.id) {
      return;
    }

    setState(() => _sendingStoryReply = true);
    _pauseStory();

    try {
      final matrixProvider = context.read<MatrixProvider>();
      final roomId = await matrixProvider.startDirectChat(story.userId);
      if (roomId == null) {
        throw Exception('Unable to open direct chat');
      }

      await matrixProvider.sendMessage(
        roomId,
        body,
        extraContent: {
          'com.xmo.story_reply': {
            'story_id': story.id,
            'story_owner_id': story.userId,
            'story_owner_name': story.userName,
            'media_type': story.mediaType.name,
            'media_url': story.mediaUrl,
            'thumbnail_url': story.thumbnailUrl,
            'text_content': story.textContent,
            'caption': story.caption,
            'created_at': story.createdAt.millisecondsSinceEpoch,
            'expires_at': story.expiresAt.millisecondsSinceEpoch,
          },
        },
      );
      _replyController.clear();
      _replyFocusNode.unfocus();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: kLimeGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to send: $e'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingStoryReply = false);
        if (!_replyFocusNode.hasFocus) _resumeStory();
      }
    }
  }

  void _insertStoryReplyEmoji(String emoji) {
    final value = _replyController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final updatedText = value.text.replaceRange(start, end, emoji);

    _replyController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _showStoryEmojiPicker(Story story) {
    if (_isOwnStory(story) ||
        _currentStoryIndex >= _currentUserStories.length ||
        _currentUserStories[_currentStoryIndex].id != story.id) {
      return;
    }
    _pauseStory();

    void switchToKeyboard() {
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _replyFocusNode.requestFocus();
      });
    }

    ReactionPicker.show(
      context,
      _insertStoryReplyEmoji,
      closeOnSelection: false,
      composer: Container(
        color: kDarkerGrey,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: _buildStoryReplyBar(
          story,
          emojiPickerOpen: true,
          onEmojiTap: switchToKeyboard,
          onSend: () {
            Navigator.pop(context);
            _sendStoryReply(story);
          },
        ),
      ),
    ).whenComplete(() {
      if (mounted && !_replyFocusNode.hasFocus && !_sendingStoryReply) {
        _resumeStory();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserStories.isEmpty) {
      return const Scaffold(
        backgroundColor: kBlack,
        body: Center(child: CircularProgressIndicator(color: kLimeGreen)),
      );
    }

    final currentStory = _currentUserStories[_currentStoryIndex];
    final isMyStory = _isOwnStory(currentStory);
    final canReply = !isMyStory && currentStory.userId.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final caption = currentStory.caption?.trim();
    final hasCaption = caption != null && caption.isNotEmpty;

    return Scaffold(
      backgroundColor: kBlack,
      body: GestureDetector(
        onTapDown: (details) {
          final screenSize = MediaQuery.sizeOf(context);
          final screenWidth = screenSize.width;
          final screenHeight = screenSize.height;
          final tapY = details.globalPosition.dy;

          // Let header and bottom action buttons handle their own taps.
          if (tapY < MediaQuery.paddingOf(context).top + 72 ||
              ((isMyStory || canReply) &&
                  tapY >
                      screenHeight - (bottomInset + (hasCaption ? 150 : 92)))) {
            return;
          }

          if (details.globalPosition.dx < screenWidth / 3) {
            _previousStory();
          } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
            _nextStory();
          }
        },
        onLongPressStart: (_) => _pauseStory(),
        onLongPressEnd: (_) => _resumeStory(),
        child: Stack(
          children: [
            // Story content
            _buildStoryContent(currentStory),

            // Top gradient overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Progress bars
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 8,
              right: 8,
              child: _buildProgressBars(),
            ),

            // Header
            Positioned(
              top: MediaQuery.paddingOf(context).top + 28,
              left: 12,
              right: 12,
              child: _buildHeader(currentStory, isMyStory),
            ),

            if (isMyStory || canReply)
              Positioned(
                key: ValueKey('story-actions:${currentStory.id}:$isMyStory'),
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  padding: EdgeInsets.fromLTRB(
                    12,
                    hasCaption ? 14 : 10,
                    12,
                    bottomInset + 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasCaption) ...[
                        _buildCaption(caption),
                        const SizedBox(height: 12),
                      ],
                      if (isMyStory)
                        _buildMyStoryActions(currentStory)
                      else
                        _buildStoryReplyBar(currentStory),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryContent(Story story) {
    if (_isVideoStory(story)) {
      final matrixProvider = context.read<MatrixProvider>();
      final mediaRequest = matrixProvider.service.getMediaRequest(
        story.mediaUrl,
      );

      if (mediaRequest != null) {
        return StoryVideoPlayer.url(
          key: ValueKey('${story.id}:${story.mediaUrl}'),
          url: mediaRequest.uri.toString(),
          httpHeaders: mediaRequest.headers,
          mimeType: story.mediaMimeType ?? 'video/mp4',
          looping: false,
          paused: _isPaused,
          enableTapToPause: false,
          onProgress: (progress) {
            if (!mounted || _activeVideoStoryId != story.id) return;
            if ((progress - _progress.value).abs() < 0.01 && progress < 1) {
              return;
            }
            _progress.value = progress;
          },
          onCompleted: () {
            if (!mounted || _activeVideoStoryId != story.id) return;
            _nextStory();
          },
        );
      }
      return _buildTextStory(story);
    }

    if (_isImageStory(story)) {
      // Convert MXC URL to HTTP URL
      final matrixProvider = context.read<MatrixProvider>();
      final mediaRequest = matrixProvider.service.getMediaRequest(
        story.mediaUrl,
      );

      if (mediaRequest != null) {
        return Center(
          child: Image.network(
            mediaRequest.uri.toString(),
            headers: mediaRequest.headers,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  color: kLimeGreen,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (_, __, ___) => _buildTextStory(story),
          ),
        );
      } else {
        return _buildTextStory(story);
      }
    } else {
      return _buildTextStory(story);
    }
  }

  bool _isVideoStory(Story story) {
    final mimeType = story.mediaMimeType?.toLowerCase() ?? '';
    return story.mediaUrl != null &&
        (story.mediaType == StoryMediaType.video ||
            mimeType.startsWith('video/') ||
            story.thumbnailUrl != null);
  }

  bool _isImageStory(Story story) {
    final mimeType = story.mediaMimeType?.toLowerCase() ?? '';
    return story.mediaUrl != null &&
        story.mediaType == StoryMediaType.image &&
        !mimeType.startsWith('video/') &&
        story.thumbnailUrl == null;
  }

  Widget _buildTextStory(Story story) {
    return Container(
      color: kDarkerGrey,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            story.textContent ?? story.caption ?? '',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBars() {
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, progress, _) {
        return Row(
          children: List.generate(_currentUserStories.length, (index) {
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: index == _currentStoryIndex
                      ? progress
                      : index < _currentStoryIndex
                      ? 1.0
                      : 0.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: kWhite,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildHeader(Story story, bool isMyStory) {
    return Row(
      children: [
        // Avatar
        StoryAvatar(
          userName: story.userName,
          avatarUrl: story.userAvatarUrl,
          size: 32,
        ),
        const SizedBox(width: 10),
        // Name and time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMyStory ? 'Your story' : story.userName,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _formatTimeAgo(story.createdAt),
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        // Close button
        IconButton(
          icon: const Icon(Icons.close, color: kWhite, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildCaption(String caption) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        caption,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: kWhite, fontSize: 15),
      ),
    );
  }

  Widget _buildMyStoryActions(Story story) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionButton(
          icon: Icons.visibility,
          label: '${story.viewCount}',
          onTap: _viewStoryViewers,
        ),
        _buildActionButton(icon: Icons.add_circle_outline, onTap: _addStory),
        _buildActionButton(icon: Icons.delete_outline, onTap: _deleteStory),
      ],
    );
  }

  Widget _buildStoryReplyBar(
    Story story, {
    bool emojiPickerOpen = false,
    VoidCallback? onEmojiTap,
    VoidCallback? onSend,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _replyController,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return AnimatedSize(
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.bottomCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: kDarkGrey,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: _sendingStoryReply
                            ? null
                            : onEmojiTap ?? () => _showStoryEmojiPicker(story),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            emojiPickerOpen
                                ? Icons.keyboard_alt_outlined
                                : Icons.emoji_emotions_outlined,
                            color: _sendingStoryReply
                                ? kMediumGrey
                                : kLightGrey,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('story-reply-field'),
                          controller: _replyController,
                          focusNode: _replyFocusNode,
                          enabled: !_sendingStoryReply,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          textAlignVertical: TextAlignVertical.center,
                          style: GoogleFonts.inter(color: kWhite, fontSize: 17),
                          decoration: InputDecoration(
                            hintText: 'Reply to story',
                            hintStyle: GoogleFonts.inter(
                              color: kLightGrey,
                              fontSize: 14,
                            ),
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
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: hasText
                    ? GestureDetector(
                        key: const ValueKey('story-reply-send'),
                        onTap: _sendingStoryReply
                            ? null
                            : onSend ?? () => _sendStoryReply(story),
                        child: Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: _sendingStoryReply ? kDarkGrey : kLimeGreen,
                            shape: BoxShape.circle,
                          ),
                          child: _sendingStoryReply
                              ? const Padding(
                                  padding: EdgeInsets.all(11),
                                  child: CircularProgressIndicator(
                                    color: kMediumGrey,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: kBlack,
                                  size: 20,
                                ),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('story-reply-send-hidden'),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    String? label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kWhite, size: 18),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
