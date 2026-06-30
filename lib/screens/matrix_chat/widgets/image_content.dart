import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../../theme.dart';
import '../media_handler.dart';

/// Image content widget for Matrix messages
class ImageContent extends StatefulWidget {
  final Event event;
  final Future<Uint8List?> Function(Event, {bool getThumbnail}) loadImageBytes;
  final void Function(Uint8List, String, Event) openFullscreenImage;
  final BorderRadius borderRadius;
  final ValueChanged<Size>? onRenderedSize;

  const ImageContent({
    super.key,
    required this.event,
    required this.loadImageBytes,
    required this.openFullscreenImage,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.onRenderedSize,
  });

  @override
  State<ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends State<ImageContent> {
  late Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = widget.loadImageBytes(widget.event);
  }

  @override
  void didUpdateWidget(covariant ImageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId ||
        oldWidget.loadImageBytes != widget.loadImageBytes) {
      _imageFuture = widget.loadImageBytes(widget.event);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxMediaWidth = math.min(
      292.0,
      math.max(160.0, screenWidth * 0.76),
    );
    final maxMediaHeight = math.min(
      336.0,
      math.max(120.0, maxMediaWidth * 1.15),
    );
    final placeholderWidth = math.min(200.0, maxMediaWidth);
    final placeholderHeight = math.min(150.0, maxMediaHeight);
    final compactPlaceholderHeight = math.min(80.0, maxMediaHeight);
    final cachedBytes = MediaHandler.getCachedImageBytes(widget.event.eventId);

    return FutureBuilder<Uint8List?>(
      initialData: cachedBytes,
      future: cachedBytes != null ? null : _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _RenderedSizeReporter(
            onSize: widget.onRenderedSize,
            child: Container(
              width: placeholderWidth,
              height: placeholderHeight,
              decoration: BoxDecoration(
                color: kDarkGrey,
                borderRadius: widget.borderRadius,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                      color: kLimeGreen, strokeWidth: 2),
                  const SizedBox(height: 8),
                  Text(
                    widget.event.body,
                    style: GoogleFonts.inter(color: kLightGrey, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }

        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _RenderedSizeReporter(
            onSize: widget.onRenderedSize,
            child: Container(
              width: placeholderWidth,
              height: compactPlaceholderHeight,
              decoration: BoxDecoration(
                color: kDarkGrey,
                borderRadius: widget.borderRadius,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image_outlined,
                      color: kLightGrey, size: 28),
                  const SizedBox(height: 4),
                  Text(widget.event.body,
                      style:
                          GoogleFonts.inter(color: kLightGrey, fontSize: 11)),
                ],
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => widget.openFullscreenImage(
              bytes, widget.event.body, widget.event),
          child: _RenderedSizeReporter(
            onSize: widget.onRenderedSize,
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxMediaWidth,
                  maxHeight: maxMediaHeight,
                ),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: placeholderWidth,
                    height: compactPlaceholderHeight,
                    decoration: BoxDecoration(
                      color: kDarkGrey,
                      borderRadius: widget.borderRadius,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image_outlined,
                            color: kLightGrey, size: 28),
                        const SizedBox(height: 4),
                        Text(widget.event.body,
                            style: GoogleFonts.inter(
                                color: kLightGrey, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RenderedSizeReporter extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size>? onSize;

  const _RenderedSizeReporter({
    required this.child,
    required this.onSize,
  });

  @override
  State<_RenderedSizeReporter> createState() => _RenderedSizeReporterState();
}

class _RenderedSizeReporterState extends State<_RenderedSizeReporter> {
  final GlobalKey _key = GlobalKey();
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
  }

  @override
  void didUpdateWidget(covariant _RenderedSizeReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
  }

  void _reportSize() {
    if (!mounted || widget.onSize == null) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final last = _lastSize;
    if (last != null &&
        (last.width - size.width).abs() < 0.5 &&
        (last.height - size.height).abs() < 0.5) {
      return;
    }
    _lastSize = size;
    widget.onSize!(size);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.child,
    );
  }
}
