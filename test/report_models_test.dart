import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/report_models.dart';

void main() {
  test('report reason codes remain stable for backend transport', () {
    expect(XmoReportReason.hateOrAbuse.code, 'hate_or_abuse');
    expect(XmoReportReason.sexualContent.code, 'sexual_content');
    expect(XmoReportReason.illegalContent.code, 'illegal_content');
    expect(XmoReportReason.spam.code, 'spam');
  });

  test('moderation report parses persisted backend data', () {
    final report = XmoModerationReport.fromJson({
      'id': 'report-1',
      'targetType': 'message',
      'contextType': 'group',
      'reporterUserId': '@alice:example.org',
      'reportedUserId': '@bob:example.org',
      'roomId': '!room:example.org',
      'eventId': r'$event',
      'reason': 'spam',
      'status': 'pending',
      'createdAt': '2026-07-18T00:00:00Z',
    });

    expect(report.targetType, XmoReportTargetType.message);
    expect(report.contextType, XmoReportContextType.group);
    expect(report.status, XmoReportStatus.pending);
    expect(report.reportedUserId, '@bob:example.org');
  });
}
