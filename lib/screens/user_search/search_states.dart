import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SEARCH STATE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class LoadingIndicator extends StatelessWidget {
  final String? message;

  const LoadingIndicator({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(color: kLimeGreen),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: const TextStyle(color: kLightGrey, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String error;

  const ErrorState({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.person_search_outlined,
                color: kMediumGrey, size: 48),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            color: kLimeGreen.withValues(alpha: 0.3),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Search for a user to start chatting',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Type a username or Matrix ID',
            style: GoogleFonts.inter(color: kMediumGrey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            'Examples: kiran, @kiran:localhost',
            style: GoogleFonts.inter(color: kMediumGrey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
