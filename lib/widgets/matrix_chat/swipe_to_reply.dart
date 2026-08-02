import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';

/// Adds a bounded right-swipe gesture without changing the wrapped message.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    this.onReply,
    this.triggerDistance = 52,
    this.maxDragDistance = 76,
  });

  final Widget child;
  final VoidCallback? onReply;
  final double triggerDistance;
  final double maxDragDistance;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset;

  @override
  void initState() {
    super.initState();
    _offset = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    final next = (_offset.value + details.delta.dx).clamp(
      0.0,
      widget.maxDragDistance,
    );
    _offset.value = next;
  }

  void _finish(DragEndDetails details) {
    final shouldReply = _offset.value >= widget.triggerDistance;
    _settle();
    if (!shouldReply) return;
    HapticFeedback.selectionClick();
    widget.onReply?.call();
  }

  void _settle() {
    _offset.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;

    return AnimatedBuilder(
      animation: _offset,
      child: widget.child,
      builder: (context, child) {
        final progress = (_offset.value / widget.triggerDistance).clamp(
          0.0,
          1.0,
        );
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Positioned(
              left: 8,
              child: IgnorePointer(
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: 0.75 + (0.25 * progress),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: kDarkGrey,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: progress >= 1 ? kLimeGreen : kMediumGrey,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        color: progress >= 1 ? kLimeGreen : kWhite,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(_offset.value, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: _update,
                onHorizontalDragEnd: _finish,
                onHorizontalDragCancel: _settle,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
