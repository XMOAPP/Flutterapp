import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

/// Online Status Indicator - Shows if user is online
class OnlineStatusIndicator extends StatelessWidget {
  final bool isOnline;
  final DateTime? lastSeen;
  final double size;
  final bool showText;

  const OnlineStatusIndicator({
    super.key,
    required this.isOnline,
    this.lastSeen,
    this.size = 9,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    if (showText) {
      return Text(
        _getStatusText(),
        style: GoogleFonts.inter(
          color: isOnline ? kLimeGreen : kLightGrey,
          fontSize: 10,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? kLimeGreen : kLightGrey,
        shape: BoxShape.circle,
        border: Border.all(
          color: kBlack,
          width: 1.5,
        ),
      ),
    );
  }

  String _getStatusText() {
    if (isOnline) return 'Online';

    if (lastSeen == null) return 'Offline';

    final now = DateTime.now();
    final difference = now.difference(lastSeen!);

    if (difference.inMinutes < 1) {
      return 'Last seen just now';
    } else if (difference.inHours < 1) {
      return 'Last seen ${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return 'Last seen ${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return 'Last seen ${difference.inDays}d ago';
    } else {
      return 'Last seen ${lastSeen!.day}/${lastSeen!.month}/${lastSeen!.year}';
    }
  }
}
