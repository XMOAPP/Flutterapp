import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../theme.dart';

/// A small non-blocking connection indicator. Matrix keeps its own sync loop;
/// this exposes its freshness to the user and offers a deterministic retry.
class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MatrixProvider>();
    if (!provider.isLoggedIn ||
        provider.connectionStatus == MatrixConnectionStatus.online) {
      return const SizedBox.shrink();
    }

    final status = provider.connectionStatus;
    final label = switch (status) {
      MatrixConnectionStatus.connecting => 'Connecting...',
      MatrixConnectionStatus.reconnecting => 'Reconnecting...',
      MatrixConnectionStatus.offline => 'Offline',
      MatrixConnectionStatus.online => '',
    };

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
            decoration: BoxDecoration(
              color: kMediumGrey.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status != MatrixConnectionStatus.offline)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      color: kLimeGreen,
                      strokeWidth: 2,
                    ),
                  )
                else
                  const Icon(Icons.cloud_off_outlined,
                      color: kLightGrey, size: 16),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: provider.retryConnection,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Retry',
                    style: GoogleFonts.inter(
                      color: kLimeGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
