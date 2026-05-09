import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/matrix_chat/attachment_option.dart';

void showChatAttachmentSheet({
  required BuildContext context,
  required VoidCallback onGallery,
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
        padding: const EdgeInsets.only(top: 16, left: 24, right: 24, bottom: 8),
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
                AttachOption(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  color: Colors.white,
                  onTap: () {
                    Navigator.pop(ctx);
                    onGallery();
                  },
                ),
                AttachOption(
                  icon: Icons.description_outlined,
                  label: 'Documents',
                  color: Colors.white,
                  onTap: () {
                    Navigator.pop(ctx);
                    onDocuments();
                  },
                ),
                AttachOption(
                  icon: Icons.person_outline,
                  label: 'Contacts',
                  color: Colors.white,
                  onTap: () {
                    Navigator.pop(ctx);
                    onContacts();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
