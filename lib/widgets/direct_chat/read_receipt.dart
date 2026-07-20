import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../../theme.dart';

/// Read Receipt Status
enum ReadReceiptStatus {
  failed, // Send failed
  sending, // Clock icon
  sent, // Single check
  delivered, // Double check (grey)
  read, // Double check (blue)
}

/// Maps the Matrix SDK's local event lifecycle to the strongest status XMO
/// can prove. A read receipt is meaningful only after the event is synced.
ReadReceiptStatus resolveReadReceiptStatus(
  EventStatus eventStatus, {
  bool isRead = false,
}) {
  if (eventStatus.isError || eventStatus.isRemoved) {
    return ReadReceiptStatus.failed;
  }
  if (eventStatus.isSending) return ReadReceiptStatus.sending;
  if (eventStatus == EventStatus.sent) return ReadReceiptStatus.sent;
  if (isRead && eventStatus.isSynced) return ReadReceiptStatus.read;
  if (eventStatus.isSynced) return ReadReceiptStatus.delivered;
  return ReadReceiptStatus.sent;
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
    return Semantics(
      label: switch (status) {
        ReadReceiptStatus.failed => 'Message failed to send',
        ReadReceiptStatus.sending => 'Message sending',
        ReadReceiptStatus.sent => 'Message sent',
        ReadReceiptStatus.delivered => 'Message delivered',
        ReadReceiptStatus.read => 'Message read',
      },
      child: switch (status) {
        ReadReceiptStatus.failed => Icon(
            Icons.error_outline_rounded,
            size: size + 1,
            color: Colors.redAccent,
          ),
        ReadReceiptStatus.sending => Icon(
            Icons.access_time,
            size: size,
            color: kLightGrey.withValues(alpha: 0.6),
          ),
        ReadReceiptStatus.sent => Icon(
            Icons.done,
            size: size,
            color: kLightGrey.withValues(alpha: 0.6),
          ),
        ReadReceiptStatus.delivered => _DoubleCheck(
            size: size,
            color: kLightGrey.withValues(alpha: 0.72),
          ),
        ReadReceiptStatus.read => _DoubleCheck(
            size: size,
            color: kAudioBlue,
          ),
      },
    );
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
