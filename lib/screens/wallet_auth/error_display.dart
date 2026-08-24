import 'package:flutter/material.dart';
import '../../widgets/common/error_display.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WALLET AUTH ERROR DISPLAY WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

class WalletErrorDisplay extends StatelessWidget {
  final String? error;

  const WalletErrorDisplay({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    return ErrorDisplay(error: error, padding: EdgeInsets.zero);
  }
}
