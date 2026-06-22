import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import '../../theme.dart';
import '../../screens/native_share_stub.dart'
    if (dart.library.io) '../../screens/native_share.dart' as native_share;
import '../../screens/web_download_stub.dart'
    if (dart.library.js_interop) '../../screens/web_download.dart'
    as web_download;

/// Fullscreen image viewer with zoom and download functionality
class FullscreenImageViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;
  final Event event;
  final Future<void> Function()? onReply;
  final Future<void> Function()? onDelete;

  const FullscreenImageViewer({
    super.key,
    required this.imageBytes,
    required this.title,
    required this.event,
    this.onReply,
    this.onDelete,
  });

  String? get _mimeType => lookupMimeType(title, headerBytes: imageBytes);

  Future<void> _saveImage(BuildContext context) async {
    try {
      await web_download.downloadFile(
        imageBytes,
        title,
        mimeType: _mimeType,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(kIsWeb ? 'Downloaded: $title' : 'Downloaded successfully'),
            backgroundColor: kLimeGreen,
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

  Future<void> _shareImage(BuildContext context) async {
    try {
      await native_share.shareFile(
        imageBytes,
        title,
        mimeType: _mimeType,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _closeAndRun(BuildContext context, Future<void> Function() action) {
    Navigator.maybePop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      action();
    });
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: kWhite, size: 28),
            color: const Color(0xFF262728),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (value) {
              if (value == 'download') {
                _saveImage(context);
              } else if (value == 'share') {
                _shareImage(context);
              } else if (value == 'reply') {
                final action = onReply;
                if (action != null) _closeAndRun(context, action);
              } else if (value == 'delete') {
                final action = onDelete;
                if (action != null) _closeAndRun(context, action);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    const Icon(Icons.download, color: kWhite, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Download',
                      style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    const Icon(Icons.share, color: kWhite, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Share',
                      style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                    ),
                  ],
                ),
              ),
              if (onReply != null)
                PopupMenuItem(
                  value: 'reply',
                  child: Row(
                    children: [
                      const Icon(Icons.reply, color: kWhite, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Reply',
                        style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              if (onDelete != null)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Delete Message',
                        style:
                            GoogleFonts.inter(color: Colors.red, fontSize: 14),
                      ),
                    ],
                  ),
                ),
            ],
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
                const Icon(Icons.broken_image_outlined,
                    color: kLightGrey, size: 64),
                const SizedBox(height: 12),
                Text('Failed to load image',
                    style: GoogleFonts.inter(color: kLightGrey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
