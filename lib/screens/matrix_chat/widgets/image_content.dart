import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import '../../../theme.dart';

/// Image content widget for Matrix messages
class ImageContent extends StatelessWidget {
  final Event event;
  final Future<Uint8List?> Function(Event, {bool getThumbnail}) loadImageBytes;
  final void Function(Uint8List, String, Event) openFullscreenImage;

  const ImageContent({
    super.key,
    required this.event,
    required this.loadImageBytes,
    required this.openFullscreenImage,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loadImageBytes(event),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: kDarkGrey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: kLimeGreen, strokeWidth: 2),
                const SizedBox(height: 8),
                Text(
                  event.body,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }

        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            width: 200,
            height: 80,
            decoration: BoxDecoration(
              color: kDarkGrey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image_outlined, color: kLightGrey, size: 28),
                const SizedBox(height: 4),
                Text(event.body, style: GoogleFonts.inter(color: kLightGrey, fontSize: 11)),
              ],
            ),
          );
        }

        return GestureDetector(
          onTap: () => openFullscreenImage(bytes, event.body, event),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 292, maxHeight: 336),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 200,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kDarkGrey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image_outlined, color: kLightGrey, size: 28),
                      const SizedBox(height: 4),
                      Text(event.body, style: GoogleFonts.inter(color: kLightGrey, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
