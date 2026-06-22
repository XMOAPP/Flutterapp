import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:googleapis_auth/auth_io.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'package:xmo_auth_server/src/endpoint_modules.dart';
import 'package:xmo_auth_server/src/health_status.dart';
import 'package:xmo_auth_server/src/request_guard.dart';
import 'package:xmo_auth_server/src/structured_logger.dart';

final String _gmail = Platform.environment['XMO_GMAIL'] ?? '';
final String _gmailAppPassword =
    Platform.environment['XMO_GMAIL_APP_PASSWORD'] ?? '';
final int _port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;
final String _thirdwebSecretKey =
    Platform.environment['XMO_THIRDWEB_SECRET_KEY'] ?? '';
final String _donationRecipientAddress =
    Platform.environment['XMO_DONATION_RECIPIENT_ADDRESS'] ??
        _defaultDonationRecipientAddress;
final String _firebaseServiceAccountJson =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_JSON'] ?? '';
final String _firebaseServiceAccountBase64 =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_BASE64'] ?? '';
final String _firebaseServiceAccountFile =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_FILE'] ?? '';
final String _firebaseProjectId =
    Platform.environment['XMO_FIREBASE_PROJECT_ID'] ?? '';

final _otpStore = <String, _OtpRecord>{};
final _random = Random.secure();
final _rateLimiter = RequestRateLimiter();
const _logger = StructuredLogger();
const _otpEndpoints = OtpEndpointModule(send: _sendOtp, verify: _verifyOtp);
const _donationEndpoints = DonationEndpointModule(_createDonationPayment);
const _pushEndpoints = PushGatewayEndpointModule(_handleMatrixPush);

const _otpTtl = Duration(minutes: 5);
const _maxAttempts = 5;
const _thirdwebBaseUrl = 'https://api.thirdweb.com';
const _baseUsdcAddress = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _defaultDonationRecipientAddress =
    '0xc1a4BF16f64f5eE26b7C73831eF8bc70f200EacB';
const _baseChainId = 8453;
const _minDonationUsd = 5.0;
const _firebaseMessagingScope =
    'https://www.googleapis.com/auth/firebase.messaging';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
  stdout.writeln('XMO auth server listening on 0.0.0.0:$_port');

  await for (final request in server) {
    await _handleRequest(request);
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  final stopwatch = Stopwatch()..start();
  _setCorsHeaders(request.response);

  try {
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && !_rateLimiter.allow(request)) {
      await _json(request, HttpStatus.tooManyRequests, {
        'error': 'Too many requests. Please try again shortly.',
      });
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/health') {
      await _json(
        request,
        HttpStatus.ok,
        buildHealthStatus(
          emailConfigured: _gmail.isNotEmpty && _gmailAppPassword.isNotEmpty,
          donationConfigured: _thirdwebSecretKey.isNotEmpty &&
              _donationRecipientAddress.isNotEmpty,
          pushConfigured: _firebaseServiceAccountJson.isNotEmpty ||
              _firebaseServiceAccountBase64.isNotEmpty ||
              _firebaseServiceAccountFile.isNotEmpty,
        ),
      );
      return;
    }

    if (request.method == 'POST' &&
        _otpEndpoints.handlesSend(request.uri.path)) {
      await _otpEndpoints.send(request);
      return;
    }

    if (request.method == 'POST' &&
        _otpEndpoints.handlesVerify(request.uri.path)) {
      await _otpEndpoints.verify(request);
      return;
    }

    if (request.method == 'POST' &&
        _donationEndpoints.handles(request.uri.path)) {
      await _donationEndpoints.create(request);
      return;
    }

    if (request.method == 'POST' && _pushEndpoints.handles(request.uri.path)) {
      await _pushEndpoints.forward(request);
      return;
    }

    await _json(request, HttpStatus.notFound, {'error': 'Not found'});
  } on _BadRequestException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  } catch (e, st) {
    _logger.error('request_failed', e, st);
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Internal server error'},
    );
  } finally {
    stopwatch.stop();
    _logger.request(
      request: request,
      statusCode: request.response.statusCode,
      elapsed: stopwatch.elapsed,
    );
  }
}

Future<void> _sendOtp(HttpRequest request) async {
  final body = await _readJson(request);
  final email = _normalizeEmail(body['email']);

  if (!_isValidEmail(email)) {
    await _json(request, HttpStatus.badRequest, {'error': 'Invalid email'});
    return;
  }

  if (_gmail.isEmpty || _gmailAppPassword.isEmpty) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Email credentials are not configured'},
    );
    return;
  }

  final otp = (_random.nextInt(900000) + 100000).toString();
  _otpStore[email] = _OtpRecord(
    code: otp,
    expiresAt: DateTime.now().toUtc().add(_otpTtl),
  );

  await _sendEmail(email, otp);
  stdout.writeln('OTP sent to $email');

  await _json(request, HttpStatus.ok, {'success': true});
}

Future<void> _verifyOtp(HttpRequest request) async {
  final body = await _readJson(request);
  final email = _normalizeEmail(body['email']);
  final otp = body['otp']?.toString().trim() ?? '';

  final record = _otpStore[email];
  if (record == null) {
    await _json(request, HttpStatus.badRequest, {'error': 'OTP not requested'});
    return;
  }

  if (DateTime.now().toUtc().isAfter(record.expiresAt)) {
    _otpStore.remove(email);
    await _json(request, HttpStatus.badRequest, {'error': 'OTP expired'});
    return;
  }

  record.attempts += 1;
  if (record.attempts > _maxAttempts) {
    _otpStore.remove(email);
    await _json(
      request,
      HttpStatus.tooManyRequests,
      {'error': 'Too many OTP attempts'},
    );
    return;
  }

  if (record.code != otp) {
    await _json(request, HttpStatus.badRequest, {'error': 'Incorrect OTP'});
    return;
  }

  _otpStore.remove(email);
  await _json(request, HttpStatus.ok, {'success': true});
}

Future<void> _createDonationPayment(HttpRequest request) async {
  final body = await _readJson(request);
  final amount = _parseAmount(body['amountUsdcSmallestUnit']);
  final donorUserId = body['donorUserId']?.toString().trim() ?? '';
  final donorDisplayName = body['donorDisplayName']?.toString().trim() ?? '';

  if (_thirdwebSecretKey.isEmpty) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Thirdweb secret key is not configured'},
    );
    return;
  }

  if (_donationRecipientAddress.isEmpty) {
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Donation recipient wallet is not configured'},
    );
    return;
  }

  if (amount == null || amount <= BigInt.zero) {
    await _json(
      request,
      HttpStatus.badRequest,
      {'error': 'Invalid donation amount'},
    );
    return;
  }

  final minSmallestUnit = BigInt.from((_minDonationUsd * 1000000).round());
  if (amount < minSmallestUnit) {
    await _json(
      request,
      HttpStatus.badRequest,
      {'error': 'Minimum donation is \$5'},
    );
    return;
  }

  final response = await _postThirdwebPayment(
    amountUsdcSmallestUnit: amount,
    donorUserId: donorUserId,
    donorDisplayName: donorDisplayName,
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    await _json(
      request,
      response.statusCode,
      {'error': _thirdwebErrorMessage(response.body)},
    );
    return;
  }

  final decoded = _decodeJsonMap(response.body);
  final result = decoded['result'];
  if (result is! Map<String, dynamic>) {
    await _json(
      request,
      HttpStatus.badGateway,
      {'error': 'Thirdweb did not return payment details'},
    );
    return;
  }

  final id = result['id']?.toString() ?? '';
  final link = result['link']?.toString() ?? '';
  if (id.isEmpty || Uri.tryParse(link) == null) {
    await _json(
      request,
      HttpStatus.badGateway,
      {'error': 'Thirdweb did not return a checkout link'},
    );
    return;
  }

  await _json(request, HttpStatus.ok, {
    'success': true,
    'payment': {
      'id': id,
      'link': link,
    },
  });
}

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
    if (content['body'] != null) 'content': content['body'].toString(),
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
    return const _PushPreview(kind: 'encrypted', label: 'Encrypted message');
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
  if (lowerEventType.startsWith('m.room.')) {
    return const _PushPreview(kind: 'room', label: 'Room updated');
  }

  final contentBody = content['body']?.toString().trim();
  return _PushPreview(
    kind: 'text',
    label: contentBody == null || contentBody.isEmpty ? 'Message' : contentBody,
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

  final contentBody = content['body']?.toString().trim();
  final lowerEventType = eventType.toLowerCase();
  final lowerMsgType = msgType.toLowerCase();
  if (lowerEventType.contains('encrypted')) return 'New encrypted message';

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
  if (lowerEventType.startsWith('m.room.')) return 'Room updated';

  if (contentBody != null && _isDisplayablePushText(contentBody)) {
    return contentBody;
  }

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
  final body = content['body']?.toString().trim();
  return body == null || body.isEmpty ? fallback : body;
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

Future<_ThirdwebResponse> _postThirdwebPayment({
  required BigInt amountUsdcSmallestUnit,
  required String donorUserId,
  required String donorDisplayName,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('$_thirdwebBaseUrl/v1/bridge/payments'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.add('x-secret-key', _thirdwebSecretKey);
    request.write(jsonEncode({
      'name': 'XMO Donation',
      'description': 'Support XMO development',
      'token': {
        'address': _baseUsdcAddress,
        'chainId': _baseChainId,
        'amount': amountUsdcSmallestUnit.toString(),
      },
      'recipient': _donationRecipientAddress,
      'purchaseData': {
        'source': 'xmo_app',
        if (donorUserId.isNotEmpty) 'donorUserId': donorUserId,
        if (donorDisplayName.isNotEmpty) 'donorDisplayName': donorDisplayName,
      },
    }));

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return _ThirdwebResponse(
      statusCode: response.statusCode,
      body: body,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  const maxRequestBytes = 1024 * 1024;
  final contentLength = request.contentLength;
  if (contentLength > maxRequestBytes) {
    throw const _BadRequestException('Request body is too large');
  }
  final content = await utf8.decoder.bind(request).join();
  if (content.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const _BadRequestException('JSON object expected');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } on FormatException {
    throw const _BadRequestException('Invalid JSON request body');
  }
}

Map<String, dynamic> _decodeJsonMap(String body) {
  if (body.trim().isEmpty) return {};
  final decoded = jsonDecode(body);
  return decoded is Map<String, dynamic> ? decoded : {};
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<dynamic>? _asList(Object? value) => value is List ? value : null;

BigInt? _parseAmount(Object? value) {
  if (value == null) return null;
  return BigInt.tryParse(value.toString().trim());
}

String _thirdwebErrorMessage(String body) {
  try {
    final decoded = _decodeJsonMap(body);
    final direct = decoded['message'] ?? decoded['error'];
    if (direct != null) return direct.toString();

    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      final nested = result['message'] ?? result['error'];
      if (nested != null) return nested.toString();
    }
  } catch (_) {
    // Fall through to a generic message.
  }
  return 'Unable to create donation checkout link';
}

Future<void> _sendEmail(String email, String otp) async {
  final smtpServer = gmail(_gmail, _gmailAppPassword);
  final message = Message()
    ..from = Address(_gmail, 'XMO Verification')
    ..recipients.add(email)
    ..subject = 'Your XMO verification code'
    ..html = '''
      <div style="font-family: Arial, sans-serif; text-align: center; padding: 24px;">
        <h2>Welcome to XMO</h2>
        <p>Your verification code is:</p>
        <h1 style="color: #9CFF2E; letter-spacing: 6px;">$otp</h1>
        <p>This code expires in 5 minutes.</p>
      </div>
    ''';

  await send(message, smtpServer);
}

String _normalizeEmail(Object? value) =>
    value?.toString().trim().toLowerCase() ?? '';

bool _isValidEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

String _redactPushKey(String pushKey) {
  if (pushKey.isEmpty) return '<empty>';
  if (pushKey.length <= 12) return '<short:${pushKey.length}>';
  return '${pushKey.substring(0, 6)}...${pushKey.substring(pushKey.length - 6)}';
}

void _setCorsHeaders(HttpResponse response) {
  response.headers.add('Access-Control-Allow-Origin', '*');
  response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
}

Future<void> _json(
  HttpRequest request,
  int statusCode,
  Map<String, dynamic> body,
) async {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

class _OtpRecord {
  final String code;
  final DateTime expiresAt;
  int attempts = 0;

  _OtpRecord({
    required this.code,
    required this.expiresAt,
  });
}

class _BadRequestException implements Exception {
  const _BadRequestException(this.message);
  final String message;
}

class _ThirdwebResponse {
  final int statusCode;
  final String body;

  const _ThirdwebResponse({
    required this.statusCode,
    required this.body,
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
