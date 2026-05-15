import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/matrix_chat/attachment_option.dart';

void showChatAttachmentSheet({
  required BuildContext context,
  required VoidCallback onGallery,
  required VoidCallback onCamera,
  required VoidCallback onAudio,
  required VoidCallback onDocuments,
  required VoidCallback onContacts,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: kDarkerGrey,
    barrierColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 16, left: 10, right: 10, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kMediumGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AttachmentOptionSlot(
                  child: AttachOption(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: Colors.white,
                    onTap: () {
                      Navigator.pop(ctx);
                      onGallery();
                    },
                  ),
                ),
                _AttachmentOptionSlot(
                  child: AttachOption(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    color: Colors.white,
                    onTap: () {
                      Navigator.pop(ctx);
                      onCamera();
                    },
                  ),
                ),
                _AttachmentOptionSlot(
                  child: AttachOption(
                    icon: Icons.audiotrack_outlined,
                    label: 'Audio',
                    color: Colors.white,
                    onTap: () {
                      Navigator.pop(ctx);
                      onAudio();
                    },
                  ),
                ),
                _AttachmentOptionSlot(
                  child: AttachOption(
                    icon: Icons.description_outlined,
                    label: 'Documents',
                    color: Colors.white,
                    onTap: () {
                      Navigator.pop(ctx);
                      onDocuments();
                    },
                  ),
                ),
                _AttachmentOptionSlot(
                  child: AttachOption(
                    icon: Icons.person_outline,
                    label: 'Contacts',
                    color: Colors.white,
                    onTap: () {
                      Navigator.pop(ctx);
                      onContacts();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AttachmentOptionSlot extends StatelessWidget {
  final Widget child;

  const _AttachmentOptionSlot({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Center(child: child),
    );
  }
}
