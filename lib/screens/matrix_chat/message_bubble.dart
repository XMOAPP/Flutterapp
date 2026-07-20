import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../../services/matrix_service.dart';
import '../../widgets/direct_chat/read_receipt.dart';
import 'message_widgets.dart';

/// Builds a message bubble for different message types (text, image, video, file, audio)
class MessageBubble extends StatelessWidget {
  final Event event;
  final String myUserId;
  final Future<Uint8List?> Function(Event, {bool getThumbnail}) loadImageBytes;
  final Future<void> Function(Event) playVideo;
  final Future<void> Function(Event) downloadAndOpenFile;
  final Future<void> Function(Event)? shareAttachment;
  final Future<void> Function(Event)? openAttachmentExternally;
  final Future<MatrixFile> Function(Event)? downloadAttachment;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  final bool isPinned;
  final void Function(Uint8List, String, Event) openFullscreenImage;

  const MessageBubble({
    super.key,
    required this.event,
    required this.myUserId,
    required this.loadImageBytes,
    required this.playVideo,
    required this.downloadAndOpenFile,
    this.shareAttachment,
    this.openAttachmentExternally,
    this.downloadAttachment,
    this.onReply,
    this.onForward,
    this.onPin,
    this.onDelete,
    this.isPinned = false,
    required this.openFullscreenImage,
  });

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');

    // Convert to 12-hour format with AM/PM
    if (hour == 0) {
      return '12:$minute AM';
    } else if (hour < 12) {
      return '$hour:$minute AM';
    } else if (hour == 12) {
      return '12:$minute PM';
    } else {
      return '${hour - 12}:$minute PM';
    }
  }

  Widget _buildMessageStatus(Event event) {
    return ReadReceipt(
      status: resolveReadReceiptStatus(event.status),
      size: 14,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMe = event.senderId == myUserId;
    final time = _formatTime(event.originServerTs);
    final senderName = MatrixService.cleanName(event.senderId);

    // Determine message type
    final msgtype = event.messageType;
    final isImage = msgtype == MessageTypes.Image;
    final isVideo = msgtype == MessageTypes.Video;
    final isAudio = msgtype == MessageTypes.Audio;
    final isFile = msgtype == MessageTypes.File;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        child: isImage || isVideo
            ? MediaMessageBubble(
                event: event,
                isMe: isMe,
                senderName: senderName,
                time: time,
                isImage: isImage,
                loadImageBytes: loadImageBytes,
                loadVideoThumbnail: (event) async => null, // Placeholder
                playVideo: playVideo,
                downloadAttachment: downloadAndOpenFile,
                shareAttachment: shareAttachment,
                onReply: onReply,
                onForward: onForward,
                onPin: onPin,
                onDelete: onDelete,
                isPinned: isPinned,
                openFullscreenImage: openFullscreenImage,
                buildMessageStatus: _buildMessageStatus,
              )
            : TextOrFileMessageBubble(
                event: event,
                isMe: isMe,
                senderName: senderName,
                time: time,
                isAudio: isAudio,
                isFile: isFile,
                downloadAndOpenFile: downloadAndOpenFile,
                shareAttachment: shareAttachment,
                openAttachmentExternally: openAttachmentExternally,
                downloadAttachment: downloadAttachment,
                onReply: onReply,
                onForward: onForward,
                onPin: onPin,
                onDelete: onDelete,
                isPinned: isPinned,
                buildMessageStatus: _buildMessageStatus,
                loadImageBytes: loadImageBytes,
              ),
      ),
    );
  }
}
