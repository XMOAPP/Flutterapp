import 'package:flutter/material.dart';
import '../../theme.dart';

/// Read Receipt Status
enum ReadReceiptStatus {
  sending, // Clock icon
  sent, // Single check
  delivered, // Double check (grey)
  read, // Double check (blue/green)
}

/// Read Receipt Widget - Shows message delivery status
class ReadReceipt extends StatelessWidget {
  final ReadReceiptStatus status;
  final double size;

  const ReadReceipt({
    super.key,
    required this.status,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ReadReceiptStatus.sending:
        return Icon(
          Icons.access_time,
          size: size,
          color: kLightGrey.withValues(alpha: 0.6),
        );

      case ReadReceiptStatus.sent:
        return Icon(
          Icons.done,
          size: size,
          color: kLightGrey.withValues(alpha: 0.6),
        );

      case ReadReceiptStatus.delivered:
        return _DoubleCheck(
          size: size,
          color: kLimeGreen,
        );

      case ReadReceiptStatus.read:
        return _DoubleCheck(size: size, color: kAudioBlue);
    }
  }
}

class _DoubleCheck extends StatelessWidget {
  final double size;
  final Color color;

  const _DoubleCheck({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.2,
      height: size * 0.72,
      child: CustomPaint(
        painter: _DoubleCheckPainter(color: color),
      ),
    );
  }
}

class _DoubleCheckPainter extends CustomPainter {
  final Color color;

  const _DoubleCheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * 0.12).clamp(1.0, 1.45).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final first = Path()
      ..moveTo(size.width * 0.08, size.height * 0.56)
      ..lineTo(size.width * 0.28, size.height * 0.74)
      ..lineTo(size.width * 0.64, size.height * 0.28);

    final second = Path()
      ..moveTo(size.width * 0.42, size.height * 0.58)
      ..lineTo(size.width * 0.58, size.height * 0.74)
      ..lineTo(size.width * 0.92, size.height * 0.26);

    canvas.drawPath(first, paint);
    canvas.drawPath(second, paint);
  }

  @override
  bool shouldRepaint(covariant _DoubleCheckPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
