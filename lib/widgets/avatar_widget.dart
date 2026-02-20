import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: imageUrl != null ? null : _parseColor(colorHex),
            image: imageUrl != null
                ? DecorationImage(
                    image: NetworkImage(imageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: imageUrl == null
              ? Center(
                  child: Text(
                    text.length > 2 ? text.substring(0, 2) : text,
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : null,
        ),
        if (showOnlineDot)
          Positioned(
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
          ),
        if (isGroup)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: BoxDecoration(
                color: kDarkGrey,
                shape: BoxShape.circle,
                border: Border.all(color: kBlack, width: 1.5),
              ),
              child: Icon(Icons.group, color: kLimeGreen, size: size * 0.22),
            ),
          ),
      ],
    );
  }
}
