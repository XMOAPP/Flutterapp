import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import '../../../theme.dart';

/// Tappable file chip for audio/file messages
class TappableFileChip extends StatelessWidget {
  final Event event;
  final bool isMe;
  final IconData icon;
  final String typeLabel;
  final bool showTypeLabel;
  final bool showDownloadIcon;
  final VoidCallback onTap;

  const TappableFileChip({
    super.key,
    required this.event,
    required this.isMe,
    required this.icon,
    required this.typeLabel,
    this.showTypeLabel = true,
    this.showDownloadIcon = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Parse file size
    String sizeStr = '';
    try {
      final info = event.content['info'] as Map<String, dynamic>?;
      if (info != null && info['size'] != null) {
        final size = info['size'] is int
            ? info['size'] as int
            : int.tryParse(info['size'].toString()) ?? 0;
        if (size > 0) {
          if (size < 1024) {
            sizeStr = '$size B';
          } else if (size < 1024 * 1024) {
            sizeStr = '${(size / 1024).toStringAsFixed(1)} KB';
          } else {
            sizeStr = '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
          }
        }
      }
    } catch (_) {}

    final detectedType = detectAttachmentType(event);
    final resolvedIcon =
        icon == Icons.insert_drive_file ? detectedType.icon : icon;
    final resolvedTypeLabel =
        typeLabel.isNotEmpty ? typeLabel : detectedType.label;

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMe
                  ? kLimeGreen.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              resolvedIcon,
              color: isMe ? kLimeGreen : kWhite,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.body,
                  style: GoogleFonts.inter(
                    color: isMe ? kLimeGreen : kWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sizeStr.isNotEmpty) ...[
                      Text(
                        '$sizeStr • ',
                        style: GoogleFonts.inter(
                          color: isMe
                              ? kLimeGreen.withValues(alpha: 0.6)
                              : kLightGrey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (showTypeLabel && resolvedTypeLabel.isNotEmpty)
                      Text(
                        resolvedTypeLabel,
                        style: GoogleFonts.inter(
                          color: isMe ? kLimeGreen : kLightGrey,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (showDownloadIcon) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.download_outlined,
                        color: isMe ? kLimeGreen : kLightGrey,
                        size: 12,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

AttachmentType detectAttachmentType(Event event) {
  final filename = _eventFileName(event);
  final mimeType = _eventMimeType(event, filename);
  return attachmentTypeFor(mimeType: mimeType, fileName: filename);
}

AttachmentType attachmentTypeFor({
  required String? mimeType,
  required String fileName,
}) {
  final normalizedMime = mimeType?.trim().toLowerCase() ?? '';
  final extension = _fileExtension(fileName);

  if (normalizedMime.startsWith('image/') ||
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg'}
          .contains(extension)) {
    return const AttachmentType('Photo', Icons.image);
  }
  if (normalizedMime.startsWith('video/') ||
      const {'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp', 'm4v'}
          .contains(extension)) {
    return const AttachmentType('Video', Icons.videocam);
  }
  if (normalizedMime.startsWith('audio/') ||
      const {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'amr'}
          .contains(extension)) {
    return const AttachmentType('Audio', Icons.headphones);
  }

  switch (extension) {
    case 'pdf':
      return const AttachmentType('PDF', Icons.picture_as_pdf);
    case 'doc':
    case 'docx':
      return const AttachmentType('Word', Icons.description);
    case 'xls':
    case 'xlsx':
    case 'csv':
      return const AttachmentType('Spreadsheet', Icons.table_chart);
    case 'ppt':
    case 'pptx':
      return const AttachmentType('Presentation', Icons.slideshow);
    case 'apk':
    case 'aab':
      return const AttachmentType('APK', Icons.android);
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return const AttachmentType('Archive', Icons.folder_zip);
    case 'txt':
    case 'rtf':
    case 'md':
      return const AttachmentType('Text', Icons.article);
    case 'json':
    case 'xml':
    case 'html':
    case 'css':
    case 'js':
    case 'ts':
    case 'dart':
    case 'java':
    case 'kt':
    case 'py':
    case 'c':
    case 'cpp':
    case 'cs':
    case 'php':
    case 'sh':
      return const AttachmentType('Code', Icons.code);
    case 'exe':
    case 'msi':
    case 'dmg':
    case 'pkg':
    case 'deb':
    case 'rpm':
      return const AttachmentType('App', Icons.apps);
  }

  if (normalizedMime.contains('pdf')) {
    return const AttachmentType('PDF', Icons.picture_as_pdf);
  }
  if (normalizedMime.contains('word') ||
      normalizedMime.contains('officedocument.wordprocessingml')) {
    return const AttachmentType('Word', Icons.description);
  }
  if (normalizedMime.contains('spreadsheet') ||
      normalizedMime.contains('excel')) {
    return const AttachmentType('Spreadsheet', Icons.table_chart);
  }
  if (normalizedMime.contains('presentation') ||
      normalizedMime.contains('powerpoint')) {
    return const AttachmentType('Presentation', Icons.slideshow);
  }
  if (normalizedMime == 'application/vnd.android.package-archive') {
    return const AttachmentType('APK', Icons.android);
  }
  if (normalizedMime.startsWith('text/')) {
    return const AttachmentType('Text', Icons.article);
  }

  return const AttachmentType('File', Icons.insert_drive_file);
}

class AttachmentType {
  final String label;
  final IconData icon;

  const AttachmentType(this.label, this.icon);
}

String _eventFileName(Event event) {
  final filename = event.content['filename'];
  if (filename is String && filename.trim().isNotEmpty) {
    return filename.trim();
  }
  return event.body.trim();
}

String? _eventMimeType(Event event, String fileName) {
  final info = event.content['info'];
  if (info is Map && info['mimetype'] is String) {
    final mimeType = (info['mimetype'] as String).trim();
    if (mimeType.isNotEmpty) return mimeType;
  }
  return lookupMimeType(fileName);
}

String _fileExtension(String fileName) {
  final name = fileName.trim().toLowerCase();
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == name.length - 1) return '';
  return name.substring(dotIndex + 1);
}
