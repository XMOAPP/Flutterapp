import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/matrix_provider.dart';
import '../../theme.dart';

class StoryAvatar extends StatelessWidget {
  final String userName;
  final String? avatarUrl;
  final double size;
  final Color backgroundColor;
  final Color textColor;
  final BoxBorder? border;
  final IconData? fallbackIcon;

  const StoryAvatar({
    super.key,
    required this.userName,
    this.avatarUrl,
    required this.size,
    this.backgroundColor = kDarkGrey,
    this.textColor = kLimeGreen,
    this.border,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _resolveAvatarUrl(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: border,
      ),
      child: ClipOval(
        child: _buildContent(resolvedUrl),
      ),
    );
  }

  Widget _buildContent(String? resolvedUrl) {
    if (resolvedUrl != null) {
      return Image.network(
        resolvedUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  String? _resolveAvatarUrl(BuildContext context) {
    final value = avatarUrl;
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final httpUrl = context.read<MatrixProvider>().service.getHttpUrl(
          value,
          width: size.round() * 3,
          height: size.round() * 3,
        );
    return httpUrl?.toString();
  }

  Widget _buildFallback() {
    if (fallbackIcon != null) {
      return Icon(
        fallbackIcon,
        color: textColor,
        size: size * 0.46,
      );
    }

    final trimmedName = userName.trim();
    final initial = trimmedName.isNotEmpty ? trimmedName[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.inter(
          color: textColor,
          fontSize: size * 0.38,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

}
