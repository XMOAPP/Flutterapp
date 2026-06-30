import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/matrix_provider.dart';
import '../../services/matrix_media_helper.dart';
import '../../theme.dart';

class StoryAvatar extends StatelessWidget {
  final String userName;
  final String? avatarUrl;
  final double size;
  final Color backgroundColor;
  final Color textColor;
  final BoxBorder? border;
  final IconData? fallbackIcon;
  final double? fallbackIconSize;

  const StoryAvatar({
    super.key,
    required this.userName,
    this.avatarUrl,
    required this.size,
    this.backgroundColor = const Color(0xFF2C2C2E),
    this.textColor = kLimeGreen,
    this.border,
    this.fallbackIcon,
    this.fallbackIconSize,
  });

  @override
  Widget build(BuildContext context) {
    final mediaRequest = _resolveAvatarRequest(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: border,
      ),
      child: ClipOval(
        child: _buildContent(mediaRequest),
      ),
    );
  }

  Widget _buildContent(MatrixMediaRequest? mediaRequest) {
    if (mediaRequest != null) {
      return Image.network(
        mediaRequest.uri.toString(),
        headers: mediaRequest.headers,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  MatrixMediaRequest? _resolveAvatarRequest(BuildContext context) {
    final value = avatarUrl;
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri == null) return null;
      return context.read<MatrixProvider>().service.getMediaRequestForUrl(uri);
    }

    return context.read<MatrixProvider>().service.getMediaRequest(
          value,
          width: size.round() * 3,
          height: size.round() * 3,
        );
  }

  Widget _buildFallback() {
    if (fallbackIcon != null) {
      return Icon(
        fallbackIcon,
        color: textColor,
        size: fallbackIconSize ?? size * 0.46,
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
