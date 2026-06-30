import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../models/story_models.dart';
import '../../providers/story_provider.dart';
import '../../providers/matrix_provider.dart';
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

  static const List<String> _storyReactionEmojis = [
    '❤️',
    '👍',
    '😂',
    '😮',
    '😢',
    '🙏',
    '🔥',
    '🎉',
    '👏',
    '💯',
    '🤔',
    '😍',
  ];

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
        _currentUserStories =
            storyProvider.myStories.where((s) => !s.isExpired).toList();
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
    if (_currentUserIndex > 0 || _currentUserIndex == -1) {
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
    if (_currentUserIndex == -1) return; // Don't mark own stories

    if (_currentStoryIndex < _currentUserStories.length) {
      final story = _currentUserStories[_currentStoryIndex];
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

  void _viewStoryViewers() {
    if (_currentStoryIndex >= _currentUserStories.length) return;

    final story = _currentUserStories[_currentStoryIndex];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewersScreen(storyId: story.id),
      ),
    );
  }

  void _addStory() {
    _progressTimer?.cancel();
    setState(() => _isPaused = true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StoryCreatorScreen(),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() => _isPaused = false);
      _loadCurrentUserStories();
    });
  }

  Future<void> _sendStoryReply(Story story) async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sendingStoryReply) return;

    await _sendStoryDirectMessage(
      story,
      text,
      successMessage: 'Reply sent',
    );
  }

  void _applyInitialStoryIndex() {
    final initialStoryId = widget.initialStoryId;
    if (initialStoryId == null || initialStoryId.isEmpty) return;
    final index =
        _currentUserStories.indexWhere((story) => story.id == initialStoryId);
    if (index != -1) _currentStoryIndex = index;
  }

  Future<void> _sendStoryReaction(Story story, String emoji) async {
    if (_sendingStoryReply) return;
    Navigator.of(context).maybePop();
    await _sendStoryDirectMessage(
      story,
      'Reacted to your story: $emoji',
      successMessage: 'Reaction sent',
    );
  }

  Future<void> _sendStoryDirectMessage(
    Story story,
    String body, {
    required String successMessage,
  }) async {
    if (story.userId.isEmpty || _currentUserIndex == -1) return;

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

  void _showStoryReactionPicker(Story story) {
    _pauseStory();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: kDarkerGrey,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'React',
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  children: _storyReactionEmojis.map((emoji) {
                    return InkWell(
                      onTap: () => _sendStoryReaction(story, emoji),
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        width: 42,
                        height: 42,
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 25),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
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
        body: Center(
          child: CircularProgressIndicator(color: kLimeGreen),
        ),
      );
    }

    final currentStory = _currentUserStories[_currentStoryIndex];
    final isMyStory = _currentUserIndex == -1;
    final canReply = !isMyStory && currentStory.userId.isNotEmpty;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: kBlack,
      body: GestureDetector(
        onTapDown: (details) {
          final mediaQuery = MediaQuery.of(context);
          final screenWidth = mediaQuery.size.width;
          final screenHeight = mediaQuery.size.height;
          final tapY = details.globalPosition.dy;

          // Let header and bottom action buttons handle their own taps.
          if (tapY < mediaQuery.padding.top + 72 ||
              (isMyStory && tapY > screenHeight - 96) ||
              (canReply && tapY > screenHeight - (bottomInset + 92))) {
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
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: _buildProgressBars(),
            ),

            // Header
            Positioned(
              top: MediaQuery.of(context).padding.top + 28,
              left: 12,
              right: 12,
              child: _buildHeader(currentStory, isMyStory),
            ),

            // Caption
            if (currentStory.caption != null)
              Positioned(
                bottom: canReply ? bottomInset + 82 : 80,
                left: 16,
                right: 16,
                child: _buildCaption(currentStory.caption!),
              ),

            // Bottom actions (for my story)
            if (isMyStory)
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: _buildMyStoryActions(currentStory),
              ),

            if (canReply)
              Positioned(
                bottom: bottomInset + 10,
                left: 12,
                right: 12,
                child: _buildStoryReplyBar(currentStory),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryContent(Story story) {
    if (_isVideoStory(story)) {
      final matrixProvider = context.read<MatrixProvider>();
      final mediaRequest =
          matrixProvider.service.getMediaRequest(story.mediaUrl);

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
      final mediaRequest =
          matrixProvider.service.getMediaRequest(story.mediaUrl);

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
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 11,
                ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        caption,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 13,
        ),
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
        _buildActionButton(
          icon: Icons.add_circle_outline,
          onTap: _addStory,
        ),
        _buildActionButton(
          icon: Icons.delete_outline,
          onTap: _deleteStory,
        ),
      ],
    );
  }

  Widget _buildStoryReplyBar(Story story) {
    return Row(
      children: [
        InkWell(
          onTap:
              _sendingStoryReply ? null : () => _showStoryReactionPicker(story),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_emotions_outlined,
              color: kWhite,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _replyController,
              builder: (context, value, _) {
                return TextField(
                  controller: _replyController,
                  focusNode: _replyFocusNode,
                  enabled: !_sendingStoryReply,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendStoryReply(story),
                  minLines: 1,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Reply to story',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    suffixIcon: value.text.trim().isEmpty
                        ? null
                        : IconButton(
                            icon: _sendingStoryReply
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: kLimeGreen,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.send_rounded,
                                    color: kLimeGreen,
                                    size: 20,
                                  ),
                            onPressed: _sendingStoryReply
                                ? null
                                : () => _sendStoryReply(story),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
