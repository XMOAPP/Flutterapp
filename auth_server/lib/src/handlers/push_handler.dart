part of xmo_auth_server;

Future<void> _handleMatrixPush(HttpRequest request) async {
  final body = await _readJson(request);
  final notification = _asMap(body['notification']);
  if (notification == null) {
    await _json(
        request, HttpStatus.badRequest, {'error': 'Missing notification'});
    return;
  }

  final devices = _asList(notification['devices']);
  if (devices == null || devices.isEmpty) {
    await _json(request, HttpStatus.ok, {'rejected': <String>[]});
    return;
  }

  final fcmConfig = await _loadFirebaseConfig();
  if (fcmConfig == null) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Firebase service account is not configured'},
    );
    return;
  }

  final fcmPayload = _buildFcmPayload(notification);
  final rejected = <String>[];
  final client = await clientViaServiceAccount(
    fcmConfig.credentials,
    const [_firebaseMessagingScope],
  );

  try {
    stdout.writeln(
      'Matrix push received: devices=${devices.length}, '
      'type=${fcmPayload.isCall ? 'call' : 'message'}, '
      'room=${notification['room_id'] ?? '-'}, '
      'event=${notification['event_id'] ?? '-'}',
    );

    for (final device in devices) {
      final deviceMap = _asMap(device);
      if (deviceMap == null) continue;

      final pushKey = deviceMap['pushkey']?.toString().trim() ?? '';
      if (pushKey.isEmpty) continue;

      final ok = await _sendFcmMessage(
        client: client,
        projectId: fcmConfig.projectId,
        token: pushKey,
        payload: fcmPayload,
      );
      stdout.writeln(
        'FCM ${ok ? 'accepted' : 'rejected'}: '
        'token=${_redactPushKey(pushKey)}, '
        'type=${fcmPayload.isCall ? 'call' : 'message'}',
      );
      if (!ok) rejected.add(pushKey);
    }
  } finally {
    client.close();
  }

  await _json(request, HttpStatus.ok, {'rejected': rejected});
}

Future<bool> _sendFcmMessage({
  required AutoRefreshingAuthClient client,
  required String projectId,
  required String token,
  required _FcmPayload payload,
}) async {
  final response = await client.post(
    Uri.parse(
      'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
    ),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'message': {
        'token': token,
        'data': payload.data,
        'android': {
          'priority': 'HIGH',
          'ttl': payload.isCall ? '30s' : '3600s',
        },
      },
    }),
  );

  if (response.statusCode >= 200 && response.statusCode < 300) {
    return true;
  }

  stderr.writeln(
    'FCM send failed ${response.statusCode}: ${response.body}',
  );
  return response.statusCode != HttpStatus.notFound &&
      response.statusCode != HttpStatus.badRequest;
}

_FcmPayload _buildFcmPayload(Map<String, dynamic> notification) {
  final content = _asMap(notification['content']) ?? const <String, dynamic>{};
  final eventType = notification['type']?.toString() ?? '';
  final msgType = content['msgtype']?.toString() ?? '';
  final isCall = _isCallNotification(eventType, msgType, content);
  final title = _notificationTitle(notification, isCall);
  final preview = _notificationPreview(content, eventType, msgType, isCall);
  final body =
      _notificationBody(notification, content, eventType, msgType, isCall);
  final avatarUrl = _notificationAvatarUrl(notification);

  final data = <String, String>{
    'title': title,
    'body': body,
    'preview_kind': preview.kind,
    'preview_label': preview.label,
    'xmo_push_type': isCall ? 'call' : 'message',
    if (notification['event_id'] != null)
      'event_id': notification['event_id'].toString(),
    if (notification['room_id'] != null)
      'room_id': notification['room_id'].toString(),
    if (notification['sender'] != null)
      'sender': notification['sender'].toString(),
    if (notification['sender_display_name'] != null)
      'sender_display_name': notification['sender_display_name'].toString(),
    if (notification['room_name'] != null)
      'room_name': notification['room_name'].toString(),
    if (eventType.isNotEmpty) 'event_type': eventType,
    if (msgType.isNotEmpty) 'msgtype': msgType,
    if (_visiblePushBody(content).isNotEmpty)
      'content': _visiblePushBody(content),
    if (_fileName(content, fallback: '').isNotEmpty)
      'filename': _fileName(content, fallback: ''),
    if (_contentMimeType(content) != null)
      'mimetype': _contentMimeType(content)!,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    if (preview.thumbnailUrl != null)
      'media_thumbnail_url': preview.thumbnailUrl!,
    if (content['xmo_event'] != null)
      'xmo_event': content['xmo_event'].toString(),
    if (content['xmo_call_kind'] != null)
      'xmo_call_kind': content['xmo_call_kind'].toString(),
    if (content['group_call_id'] != null)
      'group_call_id': content['group_call_id'].toString(),
    if (content['m.intent'] != null) 'm.intent': content['m.intent'].toString(),
    if (content['m.type'] != null) 'm.type': content['m.type'].toString(),
  };

  if (isCall) {
    data['type'] = 'm.call';
    data['call_type'] = _callType(eventType, msgType, content);
    final isGroupCall = _isXmoGroupCallPushMarker(content) ||
        _isGroupCallEventType(eventType) ||
        _isGroupCallEventType(content['type']?.toString() ?? '');
    if (isGroupCall) {
      data['group_call'] = 'true';
    }
    final callId =
        _callId(content) ?? content['group_call_id'] ?? notification['room_id'];
    if (callId != null) data['call_id'] = callId.toString();
  }

  return _FcmPayload(data: data, isCall: isCall);
}

_PushPreview _notificationPreview(
  Map<String, dynamic> content,
  String eventType,
  String msgType,
  bool isCall,
) {
  if (isCall) {
    return _PushPreview(
      kind: 'call',
      label: 'Incoming ${_callType(eventType, msgType, content)} call',
    );
  }

  final lowerEventType = eventType.toLowerCase();
  final lowerMsgType = msgType.toLowerCase();
  if (lowerEventType.contains('encrypted')) {
    return const _PushPreview(kind: 'encrypted', label: 'New message');
  }

  if (lowerMsgType.contains('image')) {
    return _PushPreview(
      kind: 'image',
      label: _captionOrLabel(content, 'Photo'),
      thumbnailUrl: _mediaPreviewUrl(content),
    );
  }
  if (lowerMsgType.contains('video')) {
    return _PushPreview(
      kind: 'video',
      label: _captionOrLabel(content, 'Video'),
      thumbnailUrl: _mediaPreviewUrl(content),
    );
  }
  if (lowerMsgType.contains('audio')) {
    final duration = _formatDuration(_contentDurationMs(content));
    if (_looksLikeVoiceMessage(content)) {
      return _PushPreview(
        kind: 'voice',
        label: 'Voice message${duration == null ? '' : ' ($duration)'}',
      );
    }
    return _PushPreview(
      kind: 'audio',
      label: _fileName(content, fallback: 'Audio'),
    );
  }
  if (lowerMsgType.contains('file')) {
    final filename = _fileName(content, fallback: 'File');
    return _PushPreview(
      kind: _attachmentKind(
        mimeType: _contentMimeType(content),
        fileName: filename,
      ),
      label: filename,
    );
  }
  if (lowerMsgType.contains('location')) {
    return const _PushPreview(kind: 'location', label: 'Location');
  }
  final contentBody = _visiblePushBody(content);
  if (_isDisplayablePushText(contentBody)) {
    return _PushPreview(kind: 'text', label: contentBody);
  }
  if (lowerEventType.startsWith('m.room.')) {
    return const _PushPreview(kind: 'room', label: 'Room updated');
  }

  return _PushPreview(
    kind: 'text',
    label: contentBody.isEmpty ? 'Message' : contentBody,
  );
}

String _notificationTitle(Map<String, dynamic> notification, bool isCall) {
  final roomName = notification['room_name']?.toString().trim();
  if (roomName != null && roomName.isNotEmpty) return roomName;

  final senderName = notification['sender_display_name']?.toString().trim();
  if (senderName != null && senderName.isNotEmpty) return senderName;

  final sender = notification['sender']?.toString().trim();
  if (sender != null && sender.isNotEmpty) return sender;

  return isCall ? 'Incoming call' : 'New message';
}

String _notificationBody(
  Map<String, dynamic> notification,
  Map<String, dynamic> content,
  String eventType,
  String msgType,
  bool isCall,
) {
  if (isCall) {
    return 'Incoming ${_callType(eventType, msgType, content)} call';
  }

  final contentBody = _visiblePushBody(content);
  final lowerEventType = eventType.toLowerCase();
  final lowerMsgType = msgType.toLowerCase();
  if (lowerEventType.contains('encrypted')) return 'New message';

  if (lowerMsgType.contains('image')) {
    return _captionOrLabel(content, 'Photo');
  }
  if (lowerMsgType.contains('video')) {
    return _captionOrLabel(content, 'Video');
  }
  if (lowerMsgType.contains('audio')) {
    final duration = _formatDuration(_contentDurationMs(content));
    if (_looksLikeVoiceMessage(content)) {
      return 'Voice message${duration == null ? '' : ' ($duration)'}';
    }
    return _fileName(content, fallback: 'Audio');
  }
  if (lowerMsgType.contains('file')) {
    return _fileName(content, fallback: 'File');
  }
  if (lowerMsgType.contains('location')) return 'Location';

  if (_isDisplayablePushText(contentBody)) {
    return contentBody;
  }

  if (lowerEventType.startsWith('m.room.')) return 'Room updated';

  final eventId = notification['event_id']?.toString();
  return eventId == null || eventId.isEmpty
      ? 'Open XMO to view this message'
      : 'New message';
}

bool _isDisplayablePushText(String text) {
  final value = text.trim();
  if (value.isEmpty) return false;
  if (value.startsWith('m.call.') || value.startsWith('m.room.')) return false;
  return true;
}

String _captionOrLabel(Map<String, dynamic> content, String label) {
  final caption = content['xmo_caption']?.toString().trim();
  if (caption != null && caption.isNotEmpty) return caption;
  return label;
}

String _fileName(Map<String, dynamic> content, {required String fallback}) {
  final filename = content['filename']?.toString().trim();
  if (filename != null && filename.isNotEmpty) return filename;
  final body = _visiblePushBody(content);
  return body.isEmpty ? fallback : body;
}

String _visiblePushBody(Map<String, dynamic> content) {
  final rawBody = content['body']?.toString() ?? '';
  return _stripPushReplyFallback(
    rawBody,
    isReply: _pushReplyEventId(content) != null,
  ).trim();
}

String? _pushReplyEventId(Map<String, dynamic> content) {
  final relatesTo = _asMap(content['m.relates_to']);
  final inReplyTo = _asMap(relatesTo?['m.in_reply_to']);
  final eventId = inReplyTo?['event_id']?.toString().trim();
  return eventId == null || eventId.isEmpty ? null : eventId;
}

String _stripPushReplyFallback(String body, {required bool isReply}) {
  if (!isReply) return body;
  final normalized = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.isEmpty || !lines.first.startsWith('> ')) return body;

  var index = 0;
  while (index < lines.length && lines[index].startsWith('> ')) {
    index++;
  }
  if (index >= lines.length || lines[index].trim().isNotEmpty) return body;
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }
  return lines.skip(index).join('\n');
}

String? _contentMimeType(Map<String, dynamic> content) {
  final info = _asMap(content['info']);
  final mimeType = info?['mimetype'] ?? content['mimetype'];
  final value = mimeType?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

String? _mediaPreviewUrl(Map<String, dynamic> content) {
  final info = _asMap(content['info']);
  final raw = info?['thumbnail_url'] ??
      content['thumbnail_url'] ??
      content['url'] ??
      info?['url'];
  final value = raw?.toString().trim();
  return value == null || value.isEmpty ? null : _mediaUrlToHttp(value);
}

String _attachmentKind({required String? mimeType, required String fileName}) {
  final normalizedMime = mimeType?.trim().toLowerCase() ?? '';
  final extension = _fileExtension(fileName);

  if (normalizedMime.startsWith('image/') ||
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg'}
          .contains(extension)) {
    return 'image';
  }
  if (normalizedMime.startsWith('video/') ||
      const {'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp', 'm4v'}
          .contains(extension)) {
    return 'video';
  }
  if (normalizedMime.startsWith('audio/') ||
      const {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'amr'}
          .contains(extension)) {
    return 'audio';
  }

  switch (extension) {
    case 'pdf':
      return 'pdf';
    case 'doc':
    case 'docx':
      return 'word';
    case 'xls':
    case 'xlsx':
    case 'csv':
      return 'spreadsheet';
    case 'ppt':
    case 'pptx':
      return 'presentation';
    case 'apk':
    case 'aab':
      return 'apk';
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return 'archive';
    case 'txt':
    case 'rtf':
    case 'md':
      return 'text_file';
    case 'json':
    case 'xml':
    case 'html':
    case 'css':
    case 'js':
    case 'ts':
    case 'dart':
    case 'java':
    case 'kt':
    case 'py':
    case 'c':
    case 'cpp':
    case 'cs':
    case 'php':
    case 'sh':
      return 'code';
    case 'exe':
    case 'msi':
    case 'dmg':
    case 'pkg':
    case 'deb':
    case 'rpm':
      return 'app';
  }

  if (normalizedMime.contains('pdf')) return 'pdf';
  if (normalizedMime.contains('word') ||
      normalizedMime.contains('officedocument.wordprocessingml')) {
    return 'word';
  }
  if (normalizedMime.contains('spreadsheet') ||
      normalizedMime.contains('excel')) {
    return 'spreadsheet';
  }
  if (normalizedMime.contains('presentation') ||
      normalizedMime.contains('powerpoint')) {
    return 'presentation';
  }
  if (normalizedMime == 'application/vnd.android.package-archive') {
    return 'apk';
  }
  if (normalizedMime.startsWith('text/')) return 'text_file';

  return 'file';
}

String _fileExtension(String fileName) {
  final name = fileName.trim().toLowerCase();
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == name.length - 1) return '';
  return name.substring(dotIndex + 1);
}

bool _looksLikeVoiceMessage(Map<String, dynamic> content) {
  final body = content['body']?.toString().toLowerCase() ?? '';
  final filename = content['filename']?.toString().toLowerCase() ?? '';
  return content.containsKey('org.matrix.msc3245.voice') ||
      body.startsWith('voice_') ||
      filename.startsWith('voice_');
}

int? _contentDurationMs(Map<String, dynamic> content) {
  final info = _asMap(content['info']);
  final rawDuration = info?['duration'] ?? content['duration'];
  if (rawDuration is int) return rawDuration;
  if (rawDuration is num) return rawDuration.toInt();
  return int.tryParse(rawDuration?.toString() ?? '');
}

String? _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return null;
  final duration = Duration(milliseconds: durationMs);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    return '${duration.inHours}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

String? _notificationAvatarUrl(Map<String, dynamic> notification) {
  for (final key in const [
    'sender_avatar_url',
    'room_avatar_url',
    'avatar_url',
    'icon_url',
  ]) {
    final value = notification[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return _mediaUrlToHttp(value);
  }
  return null;
}

String _mediaUrlToHttp(String value) {
  if (!value.startsWith('mxc://')) return value;
  final homeserver = Platform.environment['XMO_HOMESERVER_URL']
      ?.replaceFirst(RegExp(r'/$'), '');
  if (homeserver == null || homeserver.isEmpty) return value;
  final parts = value.substring('mxc://'.length).split('/');
  if (parts.length < 2) return value;
  return '$homeserver/_matrix/media/v3/thumbnail/${Uri.encodeComponent(parts[0])}/${Uri.encodeComponent(parts.sublist(1).join('/'))}?width=96&height=96&method=crop';
}

bool _isCallNotification(
  String eventType,
  String msgType,
  Map<String, dynamic> content,
) {
  if (_isXmoGroupCallPushMarker(content)) return true;

  final lowerEventType = eventType.toLowerCase();
  final lowerContentType = content['type']?.toString().toLowerCase() ?? '';
  final lowerMsgType = msgType.toLowerCase();

  if (lowerEventType.startsWith('m.call.') ||
      lowerContentType.startsWith('m.call.') ||
      _isGroupCallEventType(lowerEventType) ||
      _isGroupCallEventType(lowerContentType)) {
    return true;
  }

  final lowerIntent = content['m.intent']?.toString().toLowerCase() ?? '';
  final lowerType = content['m.type']?.toString().toLowerCase() ?? '';
  if ((lowerType == 'm.voice' || lowerType == 'm.video') &&
      (lowerIntent == 'm.ring' ||
          lowerIntent == 'm.prompt' ||
          lowerIntent == 'm.room')) {
    return true;
  }

  final hasCallId = _callId(content) != null;
  final hasCallOfferOrAnswer =
      content['offer'] != null || content['answer'] != null;
  return hasCallId && hasCallOfferOrAnswer && !lowerMsgType.startsWith('m.');
}

bool _isXmoGroupCallPushMarker(Map<String, dynamic> content) {
  final xmoEvent = content['xmo_event']?.toString().toLowerCase() ?? '';
  final pushType = content['xmo_push_type']?.toString().toLowerCase() ?? '';
  final callKind = content['xmo_call_kind']?.toString().toLowerCase() ?? '';
  final groupCall = content['group_call'];
  return xmoEvent == 'xmo.group_call_invite' ||
      (pushType == 'call' && callKind == 'group') ||
      groupCall == true ||
      groupCall?.toString().toLowerCase() == 'true';
}

bool _isGroupCallEventType(String eventType) {
  final value = eventType.toLowerCase();
  return value == 'org.matrix.msc3401.call' ||
      value == 'org.matrix.msc3401.call.member';
}

Object? _callId(Map<String, dynamic> content) {
  return content['call_id'] ??
      content['m.call_id'] ??
      content['m.call.id'] ??
      content['group_call_id'] ??
      content['id'];
}

String _callType(
  String eventType,
  String msgType,
  Map<String, dynamic> content,
) {
  final joined = [
    eventType,
    msgType,
    content['type'],
    content['call_type'],
    content['m.type'],
    content['body'],
  ].whereType<Object>().join(' ').toLowerCase();

  return joined.contains('video') ? 'video' : 'voice';
}

Future<_FirebaseConfig?> _loadFirebaseConfig() async {
  final raw = await _loadFirebaseServiceAccountJson();
  if (raw == null || raw.trim().isEmpty) return null;

  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final projectId = _firebaseProjectId.trim().isNotEmpty
      ? _firebaseProjectId.trim()
      : decoded['project_id']?.toString().trim() ?? '';
  if (projectId.isEmpty) return null;

  return _FirebaseConfig(
    projectId: projectId,
    credentials: ServiceAccountCredentials.fromJson(decoded),
  );
}

Future<String?> _loadFirebaseServiceAccountJson() async {
  if (_firebaseServiceAccountJson.trim().isNotEmpty) {
    return _firebaseServiceAccountJson;
  }
  if (_firebaseServiceAccountBase64.trim().isNotEmpty) {
    return utf8.decode(base64Decode(_firebaseServiceAccountBase64.trim()));
  }
  if (_firebaseServiceAccountFile.trim().isNotEmpty) {
    final file = File(_firebaseServiceAccountFile.trim());
    if (await file.exists()) return file.readAsString();
  }
  return null;
}

String _redactPushKey(String pushKey) {
  if (pushKey.isEmpty) return '<empty>';
  if (pushKey.length <= 12) return '<short:${pushKey.length}>';
  return '${pushKey.substring(0, 6)}...${pushKey.substring(pushKey.length - 6)}';
}

class _PushPreview {
  final String kind;
  final String label;
  final String? thumbnailUrl;

  const _PushPreview({
    required this.kind,
    required this.label,
    this.thumbnailUrl,
  });
}

class _FcmPayload {
  final Map<String, String> data;
  final bool isCall;

  const _FcmPayload({
    required this.data,
    required this.isCall,
  });
}

class _FirebaseConfig {
  final String projectId;
  final ServiceAccountCredentials credentials;

  const _FirebaseConfig({
    required this.projectId,
    required this.credentials,
  });
}
