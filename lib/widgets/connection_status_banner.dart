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
    final detail = _detailText(provider);

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: kMediumGrey.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
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
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: kWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: kLightGrey,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
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

  String? _detailText(MatrixProvider provider) {
    final parts = <String>[];
    final lastSyncAt = provider.lastSyncAt;
    if (lastSyncAt == null) {
      parts.add('Waiting for first sync');
    } else {
      final age = DateTime.now().difference(lastSyncAt);
      if (age.inMinutes >= 1) {
        parts.add('Last sync ${age.inMinutes}m ago');
      } else {
        parts.add('Last sync ${age.inSeconds.clamp(1, 59)}s ago');
      }
    }
    final pendingTransfers = provider.pendingTransferCount;
    if (pendingTransfers > 0) {
      parts.add(
          '$pendingTransfers transfer${pendingTransfers == 1 ? '' : 's'} pending');
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }
}
