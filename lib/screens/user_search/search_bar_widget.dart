import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SEARCH BAR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class UserSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onChanged;
  final VoidCallback onClear;

  const UserSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: kDarkGrey,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: TextField(
          controller: controller,
          autofocus: true,
          style: _searchTextStyle,
          decoration: InputDecoration(
            hintText: 'Search by username...',
            hintStyle: _hintTextStyle,
            prefixIcon: const Icon(Icons.search, color: kLightGrey, size: 20),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, color: kLightGrey, size: 18),
                    onPressed: onClear,
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }

  static final _searchTextStyle = GoogleFonts.inter(
    color: kWhite,
    fontSize: 14,
  );

  static final _hintTextStyle = GoogleFonts.inter(
    color: kLightGrey,
    fontSize: 14,
  );
}
