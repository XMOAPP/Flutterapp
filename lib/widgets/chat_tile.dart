import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/data_models.dart';
import 'avatar_widget.dart';

class ChatTile extends StatelessWidget {
  final ChatModel chat;
  final VoidCallback onTap;

  const ChatTile({super.key, required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: kDarkGrey,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar
            AvatarWidget(
              text: chat.avatarText,
              colorHex: chat.avatarColor,
              size: 52,
              showOnlineDot: chat.isOnline,
              isGroup: chat.isGroup,
              imageUrl: chat.imageUrl,
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              chat.name,
                              style: GoogleFonts.inter(
                                color: kWhite,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (chat.isGroup) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: kLimeGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.group,
                                      color: kLimeGreen,
                                      size: 11,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Group',
                                      style: GoogleFonts.inter(
                                        color: kLimeGreen,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        chat.time,
                        style: GoogleFonts.inter(
                          color: chat.unreadCount > 0 ? kLimeGreen : kLightGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Message row
                  Row(
                    children: [
                      if (chat.hasDoubleCheck) ...[
                        Icon(Icons.done_all, color: kLimeGreen, size: 14),
                        const SizedBox(width: 3),
                      ] else if (!chat.isGroup &&
                          chat.isRead &&
                          !chat.hasDoubleCheck) ...[
                        Icon(Icons.check, color: kLightGrey, size: 14),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          chat.lastMessage,
                          style: GoogleFonts.inter(
                            color: kLightGrey,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (chat.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kLimeGreen,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            chat.unreadCount.toString(),
                            style: GoogleFonts.inter(
                              color: kBlack,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
