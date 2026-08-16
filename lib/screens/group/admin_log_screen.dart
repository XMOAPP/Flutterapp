import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../models/group_models.dart';
import '../../providers/matrix_provider.dart';
import '../../services/group_service.dart';
import '../../services/matrix_service.dart';
import '../../theme.dart';

class AdminLogScreen extends StatefulWidget {
  final Room room;

  const AdminLogScreen({super.key, required this.room});

  @override
  State<AdminLogScreen> createState() => _AdminLogScreenState();
}

class _AdminLogScreenState extends State<AdminLogScreen> {
  late GroupService _groupService;
  List<AdminAction> _actions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _groupService = GroupService(context.read<MatrixProvider>().service);
    _loadLog();
  }

  Future<void> _loadLog() async {
    setState(() => _loading = true);
    try {
      final actions = await _groupService.getAdminLog(widget.room.id);
      if (mounted) {
        setState(() {
          _actions = actions;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[AdminLog] Failed to load admin log: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(safeUserFacingText('Failed to load admin log: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
          'Admin Log',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kLimeGreen),
            tooltip: 'Refresh',
            onPressed: _loadLog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : _actions.isEmpty
          ? Center(
              child: Text(
                'No admin actions yet',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _actions.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: kMediumGrey, height: 1),
              itemBuilder: (_, index) =>
                  _AdminActionTile(action: _actions[index]),
            ),
    );
  }
}

class _AdminActionTile extends StatelessWidget {
  final AdminAction action;

  const _AdminActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(action.type), color: kLimeGreen, size: 22),
      title: Text(
        action.label,
        style: GoogleFonts.inter(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _subtitle,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatTime(action.timestamp),
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
    );
  }

  String get _subtitle {
    final actor = MatrixService.cleanName(action.performedBy);
    final target = action.targetUser != null
        ? MatrixService.cleanName(action.targetUser!)
        : action.targetMessage;

    if (target == null || target.isEmpty) return 'By $actor';
    return 'By $actor -> $target';
  }

  IconData _iconFor(AdminActionType type) {
    switch (type) {
      case AdminActionType.memberAdded:
        return Icons.person_add_alt_1;
      case AdminActionType.memberRemoved:
        return Icons.person_remove_outlined;
      case AdminActionType.memberBanned:
        return Icons.block;
      case AdminActionType.memberUnbanned:
        return Icons.person_add_alt;
      case AdminActionType.memberPromoted:
        return Icons.add_moderator;
      case AdminActionType.memberDemoted:
        return Icons.remove_moderator_outlined;
      case AdminActionType.memberRestricted:
        return Icons.volume_off_outlined;
      case AdminActionType.memberRestrictionRemoved:
        return Icons.volume_up_outlined;
      case AdminActionType.messagePinned:
        return Icons.push_pin;
      case AdminActionType.messageUnpinned:
        return Icons.push_pin_outlined;
      case AdminActionType.settingsChanged:
        return Icons.settings_outlined;
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
