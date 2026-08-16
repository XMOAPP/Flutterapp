import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../providers/matrix_provider.dart';
import '../../services/direct_chat_service.dart';
import '../../theme.dart';
import '../../widgets/incoming_call_fullscreen_scope.dart';
import 'shared_media_screen.dart';

class SavedMessagesInfoScreen extends StatelessWidget {
  final Room room;

  const SavedMessagesInfoScreen({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return IncomingCallFullscreenScope(
      child: Scaffold(
        backgroundColor: kBlack,
        appBar: AppBar(
          backgroundColor: kBlack,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kWhite),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Saved Messages',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: kWhite, size: 28),
              color: const Color(0xFF262728),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (value) => _handleMenuAction(context, value),
              itemBuilder: (context) => [
                _menuItem(
                  'delete_all',
                  Icons.delete_outline,
                  'Delete all',
                  Colors.redAccent,
                ),
                _menuItem(
                  'view_messages',
                  Icons.chat_bubble,
                  'View as messages',
                  kWhite,
                ),
              ],
            ),
          ],
        ),
        body: SharedMediaScreen(
          room: room,
          embedded: true,
          showTitle: false,
          showDivider: false,
          height: MediaQuery.sizeOf(context).height,
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, String action) async {
    switch (action) {
      case 'delete_all':
        await _deleteAll(context);
        break;
      case 'view_messages':
        Navigator.pop(context);
        break;
    }
  }

  Future<void> _deleteAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text(
          'Delete all saved messages?',
          style: GoogleFonts.inter(color: kWhite, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will remove all messages from Saved Messages.',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final service = DirectChatService(context.read<MatrixProvider>().service);
      await service.clearChatHistory(room.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved Messages cleared'),
          backgroundColor: kLimeGreen,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeUserFacingText('Unable to delete saved messages: $e'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
