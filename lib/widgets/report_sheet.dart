import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/report_models.dart';
import '../services/report_service.dart';
import '../theme.dart';

Future<bool> showXmoReportSheet({
  required BuildContext context,
  required ReportService reportService,
  required XmoReportTargetType targetType,
  required XmoReportContextType contextType,
  required String title,
  String? reportedUserId,
  String? roomId,
  String? eventId,
  Future<void> Function()? blockUser,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kDarkerGrey,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _ReportSheet(
      reportService: reportService,
      targetType: targetType,
      contextType: contextType,
      title: title,
      reportedUserId: reportedUserId,
      roomId: roomId,
      eventId: eventId,
      blockUser: blockUser,
    ),
  );
  return result == true;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.reportService,
    required this.targetType,
    required this.contextType,
    required this.title,
    this.reportedUserId,
    this.roomId,
    this.eventId,
    this.blockUser,
  });

  final ReportService reportService;
  final XmoReportTargetType targetType;
  final XmoReportContextType contextType;
  final String title;
  final String? reportedUserId;
  final String? roomId;
  final String? eventId;
  final Future<void> Function()? blockUser;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _details = TextEditingController();
  XmoReportReason? _reason;
  bool _blockAfterReport = false;
  bool _submitting = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.reportService.submitReport(
        targetType: widget.targetType,
        contextType: widget.contextType,
        reason: reason,
        reportedUserId: widget.reportedUserId,
        roomId: widget.roomId,
        eventId: widget.eventId,
        details: _details.text,
      );
      if (_blockAfterReport && widget.blockUser != null) {
        await widget.blockUser!();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(safeUserFacingText('$error')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          16,
          18,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the reason that best describes the problem.',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...XmoReportReason.values.map((reason) => _reasonTile(reason)),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                maxLength: 500,
                maxLines: 3,
                style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Additional details (optional)',
                  hintStyle: GoogleFonts.inter(color: kLightGrey),
                  filled: true,
                  fillColor: kMediumGrey,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (widget.blockUser != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: kLimeGreen,
                  value: _blockAfterReport,
                  title: Text(
                    'Block this user after reporting',
                    style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                  ),
                  onChanged: _submitting
                      ? null
                      : (value) =>
                            setState(() => _blockAfterReport = value == true),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _reason == null || _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: kWhite,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kWhite,
                          ),
                        )
                      : const Text('Submit report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reasonTile(XmoReportReason reason) {
    final selected = _reason == reason;
    return InkWell(
      onTap: _submitting ? null : () => setState(() => _reason = reason),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? kLimeGreen : kLightGrey,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                reason.label,
                style: GoogleFonts.inter(color: kWhite, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
