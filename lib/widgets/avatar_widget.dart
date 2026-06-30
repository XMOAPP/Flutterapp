import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/matrix_media_helper.dart';
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

  @override
  Widget build(BuildContext context) {
    // Use RepaintBoundary to isolate repaints
    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildAvatar(context),
          if (showOnlineDot) _buildOnlineDot(),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    // If there's an image URL, use cached network image
    final mediaRequest = _resolveImageRequest(context);
    if (mediaRequest != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(
              mediaRequest.uri.toString(),
              headers: mediaRequest.headers,
            ),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Otherwise, show initials
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF2C2C2E),
      ),
      child: Center(
        child: Text(
          text.length > 2 ? text.substring(0, 2) : text,
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontSize: size * 0.34,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  MatrixMediaRequest? _resolveImageRequest(BuildContext context) {
    final value = imageUrl;
    if (value == null || value.isEmpty) return null;

    MatrixProvider? provider;
    try {
      provider = context.read<MatrixProvider>();
    } catch (_) {
      provider = null;
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri == null) return null;
      return provider?.service.getMediaRequestForUrl(uri) ??
          MatrixMediaRequest(uri: _withoutAccessToken(uri));
    }

    return provider?.service.getMediaRequest(
      value,
      width: size.round() * 3,
      height: size.round() * 3,
    );
  }

  Uri _withoutAccessToken(Uri uri) {
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('access_token');
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
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
