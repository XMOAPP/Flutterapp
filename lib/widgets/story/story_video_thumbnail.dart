import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../models/story_models.dart';
import '../../providers/matrix_provider.dart';
import '../../theme.dart';

class StoryVideoThumbnail extends StatefulWidget {
  final Story story;
  final BoxFit fit;
  final Widget playIcon;
  final Widget? loading;
  final Widget fallback;

  const StoryVideoThumbnail({
    super.key,
    required this.story,
    required this.playIcon,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.loading,
  });

  @override
  State<StoryVideoThumbnail> createState() => _StoryVideoThumbnailState();
}

class _StoryVideoThumbnailState extends State<StoryVideoThumbnail> {
  static final Map<String, Uint8List> _generatedCache = {};

  bool _uploadedThumbnailFailed = false;
  Future<Uint8List?>? _generatedFuture;

  @override
  void didUpdateWidget(covariant StoryVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.story.id != widget.story.id ||
        oldWidget.story.mediaUrl != widget.story.mediaUrl ||
        oldWidget.story.thumbnailUrl != widget.story.thumbnailUrl) {
      _uploadedThumbnailFailed = false;
      _generatedFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrixProvider = context.read<MatrixProvider>();
    final thumbnailUrl = widget.story.thumbnailUrl;

    if (!_uploadedThumbnailFailed && thumbnailUrl != null) {
      final httpUrl = matrixProvider.service.getHttpUrl(thumbnailUrl);
      if (httpUrl != null) {
        return _withPlayOverlay(
          Image.network(
            httpUrl.toString(),
            fit: widget.fit,
            errorBuilder: (_, __, ___) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _uploadedThumbnailFailed = true);
                }
              });
              return widget.fallback;
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return widget.loading ?? widget.fallback;
            },
          ),
        );
      }
    }

    final cacheKey = widget.story.thumbnailUrl ?? widget.story.mediaUrl ?? widget.story.id;
    final cached = _generatedCache[cacheKey];
    if (cached != null) {
      return _withPlayOverlay(
        Image.memory(cached, fit: widget.fit, gaplessPlayback: true),
      );
    }

    _generatedFuture ??= _generateFromVideoUrl(context, cacheKey);

    return FutureBuilder<Uint8List?>(
      future: _generatedFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return _withPlayOverlay(
            Image.memory(bytes, fit: widget.fit, gaplessPlayback: true),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _withPlayOverlay(widget.loading ?? widget.fallback);
        }

        return _withPlayOverlay(widget.fallback);
      },
    );
  }

  Future<Uint8List?> _generateFromVideoUrl(
    BuildContext context,
    String cacheKey,
  ) async {
    final mediaUrl = widget.story.mediaUrl;
    if (mediaUrl == null) return null;

    final matrixProvider = context.read<MatrixProvider>();
    final httpUrl = matrixProvider.service.getHttpUrl(mediaUrl);
    if (httpUrl == null) return null;

    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: httpUrl.toString(),
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        timeMs: 1000,
        quality: 75,
      );

      if (bytes != null && bytes.isNotEmpty) {
        _generatedCache[cacheKey] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _withPlayOverlay(Widget child) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Container(color: Colors.black.withValues(alpha: 0.14)),
        Center(child: widget.playIcon),
      ],
    );
  }
}

Widget storyVideoFallback({double? width, double? height}) {
  return Container(
    width: width,
    height: height,
    color: kDarkerGrey,
  );
}
