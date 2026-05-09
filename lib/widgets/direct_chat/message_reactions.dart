import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

/// Message Reactions Widget - Shows emoji reactions on messages
class MessageReactions extends StatelessWidget {
  final Map<String, int> reactions; // emoji -> count
  final VoidCallback onTap;
  final bool isMyMessage;

  const MessageReactions({
    super.key,
    required this.reactions,
    required this.onTap,
    this.isMyMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(
          top: 3,
          left: isMyMessage ? 0 : 0,
          right: isMyMessage ? 0 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: kDarkerGrey,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kMediumGrey, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: reactions.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (entry.value > 1) ...[
                    const SizedBox(width: 2),
                    Text(
                      '${entry.value}',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Reaction Picker Dialog - Shows emoji picker for reactions
class ReactionPicker extends StatelessWidget {
  final Function(String) onReactionSelected;

  const ReactionPicker({
    super.key,
    required this.onReactionSelected,
  });

  static const List<String> _quickReactions = [
    '❤️', '👍', '😂', '😮', '😢', '🙏',
    '🔥', '🎉', '👏', '💯', '🤔', '😍',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _quickReactions.map((emoji) {
          return GestureDetector(
            onTap: () {
              onReactionSelected(emoji);
              Navigator.pop(context);
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kDarkGrey,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static void show(BuildContext context, Function(String) onReactionSelected) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ReactionPicker(onReactionSelected: onReactionSelected),
      ),
    );
  }
}
