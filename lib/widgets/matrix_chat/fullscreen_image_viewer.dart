import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../theme.dart';
import '../../screens/web_download_stub.dart' if (dart.library.html) '../../screens/web_download.dart' as web_download;

/// Fullscreen image viewer with zoom and download functionality
class FullscreenImageViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;
  final Event event;

  const FullscreenImageViewer({
    super.key,
    required this.imageBytes,
    required this.title,
    required this.event,
  });

  Future<void> _saveImage(BuildContext context) async {
    try {
      web_download.downloadFile(imageBytes, title);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: $title'),
            backgroundColor: const Color(0xFF1A2A1A),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: kWhite),
            onPressed: () => _saveImage(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, color: kLightGrey, size: 64),
                const SizedBox(height: 12),
                Text('Failed to load image', style: GoogleFonts.inter(color: kLightGrey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
