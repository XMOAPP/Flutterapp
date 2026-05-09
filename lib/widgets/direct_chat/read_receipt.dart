import 'package:flutter/material.dart';
import '../../theme.dart';

/// Read Receipt Status
enum ReadReceiptStatus {
  sending,    // Clock icon
  sent,       // Single check
  delivered,  // Double check (grey)
  read,       // Double check (blue/green)
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
        return Icon(
          Icons.done_all,
          size: size,
          color: kLightGrey.withValues(alpha: 0.6),
        );
      
      case ReadReceiptStatus.read:
        return Icon(
          Icons.done_all,
          size: size,
          color: kLimeGreen,
        );
    }
  }
}
