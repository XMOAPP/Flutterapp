import 'package:flutter/material.dart';
import '../user_search_screen.dart';

/// Floating action button for creating new chats
class NewChatFAB extends StatelessWidget {
  const NewChatFAB({super.key});

  static final _fabDecoration = BoxDecoration(
    shape: BoxShape.circle,
    gradient: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xFF283848),
        Color(0xFF203040),
        Color(0xFF182030),
        Color(0xFF181820),
        Color(0xFF181828),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.22),
        blurRadius: 10,
        spreadRadius: 1,
      ),
      BoxShadow(
        color: const Color(0xFF203040).withValues(alpha: 0.38),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: _fabDecoration,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserSearchScreen()),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Image.asset(
                    'assets/images/ghost_cute_optimized.gif',
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
