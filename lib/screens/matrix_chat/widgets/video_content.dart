import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../../../theme.dart';
import '../media_handler.dart';

/// Video content widget with thumbnail preview and play button.
///
/// Uses StatefulWidget so the thumbnail Future is created once in initState
/// and never recreated on rebuilds — prevents the loading-flash on scroll.
class VideoContent extends StatefulWidget {
  final Event event;
  final Future<Uint8List?> Function(Event) loadVideoThumbnail;
  final Future<void> Function(Event) playVideo;
  final BorderRadius borderRadius;
  final ValueChanged<Size>? onRenderedSize;

  const VideoContent({
    super.key,
    required this.event,
    required this.loadVideoThumbnail,
    required this.playVideo,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.onRenderedSize,
  });

  @override
  State<VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends State<VideoContent> {
  late Future<Uint8List?> _thumbnailFuture;
  Size? _lastReportedSize;

  /// Reads the video aspect ratio from Matrix event info metadata.
  double _getAspectRatio() {
    final info = widget.event.content['info'];
    if (info is Map) {
      final w = (info['w'] as num?)?.toDouble();
      final h = (info['h'] as num?)?.toDouble();
      if (w != null && h != null && w > 0 && h > 0) return w / h;

      final thumbnailInfo = info['thumbnail_info'];
      if (thumbnailInfo is Map) {
        final thumbW = (thumbnailInfo['w'] as num?)?.toDouble();
        final thumbH = (thumbnailInfo['h'] as num?)?.toDouble();
        if (thumbW != null && thumbH != null && thumbW > 0 && thumbH > 0) {
          return thumbW / thumbH;
        }
      }
    }
    return 16 / 9;
  }

  @override
  void initState() {
    super.initState();
    // Store future once — not recreated on rebuilds.
    _thumbnailFuture = widget.loadVideoThumbnail(widget.event);
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _getAspectRatio();
    final thumbSize = _displaySizeForRatio(
      aspectRatio,
      MediaQuery.sizeOf(context).width,
    );
    final thumbWidth = thumbSize.width;
    final thumbHeight = thumbSize.height;
    _reportRenderedSize(thumbSize);

    // Check global static cache synchronously
    final cachedBytes = MediaHandler.getCachedThumbnail(widget.event.eventId);

    return FutureBuilder<Uint8List?>(
      initialData: cachedBytes,
      future: cachedBytes != null ? null : _thumbnailFuture,
      builder: (context, snapshot) {
        final thumbnailBytes = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting &&
            thumbnailBytes == null;

        return GestureDetector(
          onTap: () => widget.playVideo(widget.event),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: SizedBox(
              width: thumbWidth,
              height: thumbHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Thumbnail, styled placeholder, or loading shimmer
                  if (thumbnailBytes != null && thumbnailBytes.isNotEmpty)
                    Image.memory(
                      thumbnailBytes,
                      fit: BoxFit.cover,
                      width: thumbWidth,
                      errorBuilder: (_, __, ___) =>
                          const _VideoPlaceholder(isLoading: false),
                    )
                  else
                    _VideoPlaceholder(isLoading: isLoading),

                  // Gradient at the bottom (only when thumbnail is loaded)
                  if (thumbnailBytes != null && thumbnailBytes.isNotEmpty)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Play button — always visible and tappable
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
              ),
            ),
          ),
        );
      },
    );
  }

  Size _displaySizeForRatio(double aspectRatio, double screenWidth) {
    final maxWidth = math.min(
      292.0,
      math.max(160.0, screenWidth * 0.76),
    );
    final maxHeight = math.min(
      360.0,
      math.max(140.0, maxWidth * 1.23),
    );
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

  void _reportRenderedSize(Size size) {
    if (widget.onRenderedSize == null) return;
    final last = _lastReportedSize;
    if (last != null &&
        (last.width - size.width).abs() < 0.5 &&
        (last.height - size.height).abs() < 0.5) {
      return;
    }
    _lastReportedSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onRenderedSize!(size);
    });
  }
}

// ── Styled placeholder shown while thumbnail loads or when generation fails ──

class _VideoPlaceholder extends StatelessWidget {
  final bool isLoading;
  const _VideoPlaceholder({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C2B1C), Color(0xFF111111)],
        ),
      ),
      child: Stack(
        children: [
          // Subtle film icon behind the play button
          Center(
            child: Icon(
              Icons.video_file_outlined,
              color: Colors.white.withValues(alpha: 0.12),
              size: 64,
            ),
          ),
          // Tiny spinner in the corner only while loading
          if (isLoading)
            Positioned(
              top: 8,
              right: 8,
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: kLimeGreen.withValues(alpha: 0.7),
                  strokeWidth: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
