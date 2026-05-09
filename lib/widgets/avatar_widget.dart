import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OPTIMIZED AVATAR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class AvatarWidget extends StatelessWidget {
  final String text;
  final String? colorHex;
  final double size;
  final String? imageUrl;
  final bool showOnlineDot;
  final bool isGroup;

  const AvatarWidget({
    super.key,
    required this.text,
    this.colorHex,
    this.size = 50,
    this.imageUrl,
    this.showOnlineDot = false,
    this.isGroup = false,
  });

  Color _parseColor(String? hex) {
    if (hex == null) return kMediumGrey;
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    // Use RepaintBoundary to isolate repaints
    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildAvatar(),
          if (showOnlineDot) _buildOnlineDot(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final color = _parseColor(colorHex);
    
    // If there's an image URL, use cached network image
    if (imageUrl != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(imageUrl!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Otherwise, show initials
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: Center(
        child: Text(
          text.length > 2 ? text.substring(0, 2) : text,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: size * 0.34,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineDot() {
    return Positioned(
      bottom: 1,
      right: 1,
      child: Container(
        width: size * 0.26,
        height: size * 0.26,
        decoration: BoxDecoration(
          color: kLimeGreen,
          shape: BoxShape.circle,
          border: Border.all(color: kBlack, width: 2),
        ),
      ),
    );
  }
}
