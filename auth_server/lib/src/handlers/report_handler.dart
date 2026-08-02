part of xmo_auth_server;

const _reportTargetTypes = {'message', 'user', 'group', 'channel'};
const _reportContextTypes = {'direct', 'group', 'channel'};
const _reportReasons = {
  'spam',
  'harassment',
  'hate_or_abuse',
  'sexual_content',
  'violence',
  'impersonation',
  'illegal_content',
  'other',
};
const _reportStatuses = {'pending', 'reviewed', 'actioned', 'dismissed'};
final _reportMemoryStore = <String, _StoredReport>{};
Future<void> _reportStoreTail = Future<void>.value();

Future<void> _submitReport(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }
  final reporterUserId = await _userDirectoryWhoami(token);
  final body = await _readJson(request);
  final targetType =
      _requiredReportValue(body, 'targetType', _reportTargetTypes);
  final contextType =
      _requiredReportValue(body, 'contextType', _reportContextTypes);
  final reason = _requiredReportValue(body, 'reason', _reportReasons);
  final reportedUserId = _reportIdentifier(body['reportedUserId'], '@');
  final roomId = _reportIdentifier(body['roomId'], '!');
  final eventId = _reportIdentifier(body['eventId'], r'$');
  final details = _reportText(body['details'], 500);

  if ((targetType == 'user' && contextType != 'direct') ||
      (targetType == 'group' && contextType != 'group') ||
      (targetType == 'channel' && contextType != 'channel')) {
    throw const _BadRequestException('Invalid report context');
  }

  if (targetType == 'message' &&
      (roomId == null || eventId == null || reportedUserId == null)) {
    throw const _BadRequestException(
      'Message reports require roomId, eventId, and reportedUserId',
    );
  }
  if ((targetType == 'group' || targetType == 'channel') && roomId == null) {
    throw const _BadRequestException('Room reports require roomId');
  }
  if (targetType == 'user' && reportedUserId == null) {
    throw const _BadRequestException('User reports require reportedUserId');
  }
  if (reportedUserId == reporterUserId) {
    throw const _BadRequestException('You cannot report yourself');
  }

  var matrixReported = false;
  if (targetType == 'message') {
    matrixReported = await _forwardMatrixEventReport(
      token: token,
      roomId: roomId!,
      eventId: eventId!,
      reason: '$reason${details == null ? '' : ': $details'}',
    );
  }

  final now = DateTime.now().toUtc();
  final report = await _withReportStore((reports) {
    for (final existing in reports.values) {
      final sameTarget = existing.reporterUserId == reporterUserId &&
          existing.targetType == targetType &&
          existing.contextType == contextType &&
          existing.roomId == roomId &&
          existing.eventId == eventId &&
          existing.reportedUserId == reportedUserId;
      if (sameTarget && now.difference(existing.createdAt).inHours < 24) {
        return existing;
      }
    }
    final created = _StoredReport(
      id: _newReportId(),
      targetType: targetType,
      contextType: contextType,
      reporterUserId: reporterUserId,
      reportedUserId: reportedUserId,
      roomId: roomId,
      eventId: eventId,
      reason: reason,
      details: details,
      status: 'pending',
      createdAt: now,
    );
    reports[created.id] = created;
    return created;
  });

  await _json(request, HttpStatus.ok, {
    'success': true,
    'reportId': report.id,
    'matrixReported': matrixReported,
  });
}

Future<void> _listReports(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized,
        {'error': 'Missing XMO session token'});
    return;
  }
  final reviewerUserId = await _userDirectoryWhoami(token);
  final body = await _readJson(request);
  final global = body['global'] == true;
  final roomId = _reportIdentifier(body['roomId'], '!');
  if (global) {
    if (!await _isSynapseServerAdmin(reviewerUserId)) {
      await _json(request, HttpStatus.forbidden,
          {'error': 'Server administrator access required'});
      return;
    }
  } else if (roomId == null ||
      !await _canReviewRoomReports(
        token: token,
        userId: reviewerUserId,
        roomId: roomId,
      )) {
    await _json(
        request, HttpStatus.forbidden, {'error': 'Moderator access required'});
    return;
  }
  final limit = ((body['limit'] as num?)?.toInt() ?? 200).clamp(1, 500).toInt();
  final reports = (await _readReports()).values.where((report) {
    if (global) return true;
    return report.roomId == roomId && report.contextType != 'direct';
  }).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  await _json(request, HttpStatus.ok, {
    'success': true,
    'reports': reports.take(limit).map((report) => report.toJson()).toList(),
  });
}

Future<void> _updateReport(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized,
        {'error': 'Missing XMO session token'});
    return;
  }
  final reviewerUserId = await _userDirectoryWhoami(token);
  final body = await _readJson(request);
  final reportId = _reportText(body['reportId'], 100);
  final status = _requiredReportValue(body, 'status', _reportStatuses);
  final moderatorNote = _reportText(body['moderatorNote'], 500);
  if (reportId == null)
    throw const _BadRequestException('reportId is required');

  final reports = await _readReports();
  final existing = reports[reportId];
  if (existing == null) {
    await _json(request, HttpStatus.notFound, {'error': 'Report not found'});
    return;
  }
  final isServerAdmin = await _isSynapseServerAdmin(reviewerUserId);
  final roomId = existing.roomId;
  final isRoomModerationTarget = existing.contextType != 'direct';
  final canReviewRoom = !isServerAdmin &&
      isRoomModerationTarget &&
      roomId != null &&
      await _canReviewRoomReports(
        token: token,
        userId: reviewerUserId,
        roomId: roomId,
      );
  if (!isServerAdmin && !canReviewRoom) {
    await _json(
        request, HttpStatus.forbidden, {'error': 'Moderator access required'});
    return;
  }

  await _withReportStore((values) {
    final current = values[reportId] ?? existing;
    values[reportId] = current.copyWith(
      status: status,
      moderatorNote: moderatorNote,
      reviewedBy: reviewerUserId,
      reviewedAt: DateTime.now().toUtc(),
    );
    return values[reportId]!;
  });
  await _json(request, HttpStatus.ok, {'success': true});
}

Future<bool> _isSynapseServerAdmin(String userId) async {
  if (_reportConfig.synapseAdminToken.isEmpty) return false;
  final uri = Uri.parse(_reportConfig.homeserverUrl).replace(
    pathSegments: ['_synapse', 'admin', 'v2', 'users', userId],
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${_reportConfig.synapseAdminToken}',
    );
    final response = await request.close().timeout(const Duration(seconds: 12));
    final raw = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    return _decodeJsonMap(raw)['admin'] == true;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<bool> _forwardMatrixEventReport({
  required String token,
  required String roomId,
  required String eventId,
  required String reason,
}) async {
  final uri = Uri.parse(_reportConfig.homeserverUrl).replace(
    pathSegments: [
      '_matrix',
      'client',
      'v3',
      'rooms',
      roomId,
      'report',
      eventId
    ],
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.postUrl(uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..contentType = ContentType.json;
    request.write(jsonEncode({'reason': reason, 'score': -100}));
    final response = await request.close().timeout(const Duration(seconds: 12));
    await response.drain<void>();
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<bool> _canReviewRoomReports({
  required String token,
  required String userId,
  required String roomId,
}) async {
  final uri = Uri.parse(_reportConfig.homeserverUrl).replace(
    pathSegments: [
      '_matrix',
      'client',
      'v3',
      'rooms',
      roomId,
      'state',
      'm.room.power_levels'
    ],
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(const Duration(seconds: 12));
    final raw = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    final content = _decodeJsonMap(raw);
    final users = _asMap(content['users']) ?? const <String, dynamic>{};
    final userLevel = (users[userId] as num?)?.toInt() ??
        (content['users_default'] as num?)?.toInt() ??
        0;
    return userLevel >= 50;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

String _requiredReportValue(
  Map<String, dynamic> body,
  String key,
  Set<String> allowed,
) {
  final value = body[key]?.toString().trim().toLowerCase();
  if (value == null || !allowed.contains(value)) {
    throw _BadRequestException('Invalid $key');
  }
  return value;
}

String? _reportIdentifier(Object? value, String prefix) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || !text.startsWith(prefix)) return null;
  return text.length > 300 ? null : text;
}

String? _reportText(Object? value, int maxLength) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text.length > maxLength ? text.substring(0, maxLength) : text;
}

String _newReportId() {
  final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Future<T> _withReportStore<T>(
  T Function(Map<String, _StoredReport> reports) operation,
) {
  final completer = Completer<T>();
  _reportStoreTail = _reportStoreTail.then((_) async {
    try {
      final reports = await _readReports();
      final result = operation(reports);
      await _writeReports(reports);
      completer.complete(result);
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  });
  return completer.future;
}

Future<Map<String, _StoredReport>> _readReports() async {
  if (_reportConfig.dataFile.isEmpty) {
    return Map<String, _StoredReport>.from(_reportMemoryStore);
  }
  final file = File(_reportConfig.dataFile);
  if (!await file.exists()) return {};
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return {};
    final values = <String, _StoredReport>{};
    for (final value in decoded.values) {
      final map = _asMap(value);
      if (map == null) continue;
      final report = _StoredReport.tryFromJson(map);
      if (report != null) values[report.id] = report;
    }
    return values;
  } catch (_) {
    return {};
  }
}

Future<void> _writeReports(Map<String, _StoredReport> reports) async {
  if (_reportConfig.dataFile.isEmpty) {
    _reportMemoryStore
      ..clear()
      ..addAll(reports);
    return;
  }
  final file = File(_reportConfig.dataFile);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(
    reports.map((key, report) => MapEntry(key, report.toJson())),
  ));
}

class ReportConfig {
  const ReportConfig({
    required this.homeserverUrl,
    required this.dataFile,
    required this.synapseAdminToken,
  });

  factory ReportConfig.fromEnvironment(Map<String, String> env) {
    final homeserverUrl = env['XMO_HOMESERVER_URL'] ?? 'http://synapse:8008';
    final explicit = env['XMO_REPORT_DATA_FILE'] ?? '';
    final authData = env['XMO_AUTH_DATA_FILE'] ?? '';
    var dataFile = explicit;
    if (dataFile.isEmpty && authData.isNotEmpty) {
      final file = File(authData);
      dataFile = '${file.parent.path}${Platform.pathSeparator}reports.json';
    }
    return ReportConfig(
      homeserverUrl: homeserverUrl,
      dataFile: dataFile,
      synapseAdminToken:
          env['XMO_SYNAPSE_ADMIN_TOKEN'] ?? env['SYNAPSE_ADMIN_TOKEN'] ?? '',
    );
  }

  final String homeserverUrl;
  final String dataFile;
  final String synapseAdminToken;
  bool get isConfigured => homeserverUrl.trim().isNotEmpty;
}

class _StoredReport {
  const _StoredReport({
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
    this.reviewedBy,
    this.reviewedAt,
    this.moderatorNote,
  });

  final String id;
  final String targetType;
  final String contextType;
  final String reporterUserId;
  final String? reportedUserId;
  final String? roomId;
  final String? eventId;
  final String reason;
  final String? details;
  final String status;
  final DateTime createdAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? moderatorNote;

  _StoredReport copyWith({
    required String status,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? moderatorNote,
  }) =>
      _StoredReport(
        id: id,
        targetType: targetType,
        contextType: contextType,
        reporterUserId: reporterUserId,
        reportedUserId: reportedUserId,
        roomId: roomId,
        eventId: eventId,
        reason: reason,
        details: details,
        status: status,
        createdAt: createdAt,
        reviewedBy: reviewedBy,
        reviewedAt: reviewedAt,
        moderatorNote: moderatorNote,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetType': targetType,
        'contextType': contextType,
        'reporterUserId': reporterUserId,
        if (reportedUserId != null) 'reportedUserId': reportedUserId,
        if (roomId != null) 'roomId': roomId,
        if (eventId != null) 'eventId': eventId,
        'reason': reason,
        if (details != null) 'details': details,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        if (reviewedBy != null) 'reviewedBy': reviewedBy,
        if (reviewedAt != null) 'reviewedAt': reviewedAt!.toIso8601String(),
        if (moderatorNote != null) 'moderatorNote': moderatorNote,
      };

  static _StoredReport? tryFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (id == null || createdAt == null) return null;
    return _StoredReport(
      id: id,
      targetType: json['targetType']?.toString() ?? 'message',
      contextType: json['contextType']?.toString() ?? 'direct',
      reporterUserId: json['reporterUserId']?.toString() ?? '',
      reportedUserId: json['reportedUserId']?.toString(),
      roomId: json['roomId']?.toString(),
      eventId: json['eventId']?.toString(),
      reason: json['reason']?.toString() ?? 'other',
      details: json['details']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      createdAt: createdAt,
      reviewedBy: json['reviewedBy']?.toString(),
      reviewedAt: DateTime.tryParse(json['reviewedAt']?.toString() ?? ''),
      moderatorNote: json['moderatorNote']?.toString(),
    );
  }
}
