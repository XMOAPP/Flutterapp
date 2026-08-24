enum XmoReportTargetType { message, user, group, channel }

enum XmoReportContextType { direct, group, channel }

enum XmoReportReason {
  spam,
  harassment,
  hateOrAbuse,
  sexualContent,
  violence,
  impersonation,
  illegalContent,
  other,
}

extension XmoReportReasonDetails on XmoReportReason {
  String get code => switch (this) {
    XmoReportReason.hateOrAbuse => 'hate_or_abuse',
    XmoReportReason.sexualContent => 'sexual_content',
    XmoReportReason.illegalContent => 'illegal_content',
    _ => name,
  };

  String get label => switch (this) {
    XmoReportReason.spam => 'Spam or scam',
    XmoReportReason.harassment => 'Harassment or bullying',
    XmoReportReason.hateOrAbuse => 'Hate or abusive content',
    XmoReportReason.sexualContent => 'Sexual content',
    XmoReportReason.violence => 'Violence or threats',
    XmoReportReason.impersonation => 'Impersonation',
    XmoReportReason.illegalContent => 'Illegal content',
    XmoReportReason.other => 'Other',
  };
}

enum XmoReportStatus { pending, reviewed, actioned, dismissed }

class XmoModerationReport {
  const XmoModerationReport({
    required this.id,
    required this.targetType,
    required this.contextType,
    required this.reporterUserId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.reportedUserId,
    this.roomId,
    this.eventId,
    this.details,
    this.moderatorNote,
  });

  factory XmoModerationReport.fromJson(Map<String, dynamic> json) {
    return XmoModerationReport(
      id: json['id']?.toString() ?? '',
      targetType: XmoReportTargetType.values.firstWhere(
        (value) => value.name == json['targetType'],
        orElse: () => XmoReportTargetType.message,
      ),
      contextType: XmoReportContextType.values.firstWhere(
        (value) => value.name == json['contextType'],
        orElse: () => XmoReportContextType.direct,
      ),
      reporterUserId: json['reporterUserId']?.toString() ?? '',
      reportedUserId: json['reportedUserId']?.toString(),
      roomId: json['roomId']?.toString(),
      eventId: json['eventId']?.toString(),
      reason: json['reason']?.toString() ?? 'other',
      details: json['details']?.toString(),
      status: XmoReportStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => XmoReportStatus.pending,
      ),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      moderatorNote: json['moderatorNote']?.toString(),
    );
  }

  final String id;
  final XmoReportTargetType targetType;
  final XmoReportContextType contextType;
  final String reporterUserId;
  final String? reportedUserId;
  final String? roomId;
  final String? eventId;
  final String reason;
  final String? details;
  final XmoReportStatus status;
  final DateTime createdAt;
  final String? moderatorNote;
}
