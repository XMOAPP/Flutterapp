import 'dart:math' as math;
import 'package:flutter/material.dart';

class VoiceWaveform extends StatelessWidget {
  final List<double> bars;
  final Color color;
  final Color inactiveColor;
  final double progress;
  final double height;
  final ValueChanged<double>? onSeek;

  const VoiceWaveform({
    super.key,
    this.bars = const [],
    required this.color,
    required this.inactiveColor,
    this.progress = 0,
    this.height = 34,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekFromPosition(Offset localPosition) {
          final width = constraints.maxWidth;
          if (onSeek == null || !width.isFinite || width <= 0) return;
          onSeek!((localPosition.dx / width).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSeek == null
              ? null
              : (details) => seekFromPosition(details.localPosition),
          onHorizontalDragStart: onSeek == null
              ? null
              : (details) => seekFromPosition(details.localPosition),
          onHorizontalDragUpdate: onSeek == null
              ? null
              : (details) => seekFromPosition(details.localPosition),
          child: SizedBox(
            height: height,
            child: CustomPaint(
              painter: _VoiceWaveformPainter(
                bars: bars.isEmpty ? _fallbackBars : bars,
                color: color,
                inactiveColor: inactiveColor,
                progress: progress.clamp(0, 1),
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  static const _fallbackBars = <double>[
    .18,
    .35,
    .25,
    .48,
    .32,
    .62,
    .44,
    .72,
    .38,
    .55,
    .28,
    .46,
    .34,
    .64,
    .42,
    .78,
    .36,
    .58,
    .30,
    .50,
    .40,
    .66,
    .48,
    .82,
    .44,
    .60,
    .32,
    .54,
    .38,
    .70,
    .46,
    .57,
    .30,
    .48,
    .26,
    .40,
  ];
}

class _VoiceWaveformPainter extends CustomPainter {
  final List<double> bars;
  final Color color;
  final Color inactiveColor;
  final double progress;

  _VoiceWaveformPainter({
    required this.bars,
    required this.color,
    required this.inactiveColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    const barWidth = 3.0;
    const gap = 5.0;
    const step = barWidth + gap;
    final visibleCount = math.max(1, (size.width / step).floor());
    final start = math.max(0, bars.length - visibleCount);
    final visibleBars = bars.skip(start).take(visibleCount).toList();
    final activeUntil = visibleBars.length * progress;

    for (var i = 0; i < visibleBars.length; i++) {
      final normalized = visibleBars[i].clamp(0.08, 1.0);
      final barHeight = math.max(5.0, size.height * normalized);
      final x = i * step;
      final y = (size.height - barHeight) / 2;
      final paint = Paint()
        ..color = i <= activeUntil ? color : inactiveColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.bars != bars ||
        oldDelegate.color != color ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.progress != progress;
  }
}
