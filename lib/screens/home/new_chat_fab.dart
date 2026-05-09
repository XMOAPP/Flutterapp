import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../user_search_screen.dart';

/// Floating action button for creating new chats
class NewChatFAB extends StatelessWidget {
  const NewChatFAB({super.key});

  static final _fabDecoration = BoxDecoration(
    shape: BoxShape.circle,
    boxShadow: [
      BoxShadow(
        color: kWhite.withValues(alpha: 0.15),
        blurRadius: 15,
        spreadRadius: 2,
      ),
    ],
  );

  static final _containerDecoration = BoxDecoration(
    shape: BoxShape.circle,
    color: kWhite.withValues(alpha: 0.01),
    border: Border.all(
      color: kWhite.withValues(alpha: 0.2),
      width: 1,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: _fabDecoration,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: DecoratedBox(
              decoration: _containerDecoration,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UserSearchScreen(),
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.chat_outlined,
                      color: kLimeGreen,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
