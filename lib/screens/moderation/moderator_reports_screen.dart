import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../models/report_models.dart';
import '../../providers/matrix_provider.dart';
import '../../services/report_service.dart';
import '../../theme.dart';

class ModeratorReportsScreen extends StatefulWidget {
  const ModeratorReportsScreen({super.key, this.room});

  final Room? room;

  @override
  State<ModeratorReportsScreen> createState() => _ModeratorReportsScreenState();
}

class _ModeratorReportsScreenState extends State<ModeratorReportsScreen> {
  late final ReportService _service;
  List<XmoModerationReport> _reports = const [];
  bool _loading = true;
  bool _canReviewGlobal = false;

  @override
  void initState() {
    super.initState();
    _service = ReportService(context.read<MatrixProvider>().service);
    _load();
    if (widget.room != null) _checkGlobalAccess();
  }

  Future<void> _checkGlobalAccess() async {
    final allowed = await _service.canReviewGlobalReports();
    if (mounted) setState(() => _canReviewGlobal = allowed);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final reports = widget.room == null
          ? await _service.listGlobalReports()
          : await _service.listRoomReports(widget.room!.id);
      if (mounted) setState(() => _reports = reports);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(
    XmoModerationReport report,
    XmoReportStatus status,
  ) async {
    try {
      await _service.updateReport(reportId: report.id, status: status);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        title: Text(
          widget.room == null ? 'Server reports' : 'Reports',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_canReviewGlobal)
            IconButton(
              tooltip: 'Review all server reports',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ModeratorReportsScreen(),
                ),
              ),
              icon: const Icon(Icons.admin_panel_settings_outlined,
                  color: kWhite),
            ),
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, color: kWhite),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : _reports.isEmpty
              ? Center(
                  child: Text(
                    widget.room == null
                        ? 'No reports awaiting server review'
                        : 'No reports for this room',
                    style: GoogleFonts.inter(color: kLightGrey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: kLimeGreen,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reports.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) => _reportCard(_reports[index]),
                  ),
                ),
    );
  }

  Widget _reportCard(XmoModerationReport report) {
    final target = switch (report.targetType) {
      XmoReportTargetType.message => 'Message',
      XmoReportTargetType.user => 'User',
      XmoReportTargetType.group => 'Group',
      XmoReportTargetType.channel => 'Channel',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11171D),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: Colors.redAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$target report',
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                report.status.name,
                style: GoogleFonts.inter(
                  color: report.status == XmoReportStatus.pending
                      ? kLimeGreen
                      : kLightGrey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Reason: ${report.reason.replaceAll('_', ' ')}',
              style: GoogleFonts.inter(color: kWhite, fontSize: 13)),
          Text('Context: ${report.contextType.name}',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 12)),
          if (report.reportedUserId != null)
            Text('Reported: ${report.reportedUserId}',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 12)),
          Text('Reporter: ${report.reporterUserId}',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 12)),
          if (report.eventId != null)
            Text('Event: ${report.eventId}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 11)),
          if (report.details?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(report.details!,
                style: GoogleFonts.inter(color: kWhite, fontSize: 13)),
          ],
          if (report.status == XmoReportStatus.pending) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusButton(report, XmoReportStatus.reviewed, 'Reviewed'),
                _statusButton(report, XmoReportStatus.actioned, 'Action taken'),
                _statusButton(report, XmoReportStatus.dismissed, 'Dismiss'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusButton(
    XmoModerationReport report,
    XmoReportStatus status,
    String label,
  ) {
    return OutlinedButton(
      onPressed: () => _setStatus(report, status),
      style: OutlinedButton.styleFrom(
        foregroundColor: kWhite,
        side: const BorderSide(color: kLightGrey),
      ),
      child: Text(label),
    );
  }
}
