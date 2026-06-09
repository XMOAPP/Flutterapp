import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:googleapis_auth/auth_io.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

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
  _setCorsHeaders(request.response);

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  try {
    if (request.method == 'GET' && request.uri.path == '/health') {
      await _json(request, HttpStatus.ok, {'ok': true});
      return;
    }

    if (request.method == 'POST' && _isSendPath(request.uri.path)) {
      await _sendOtp(request);
      return;
    }

    if (request.method == 'POST' && _isVerifyPath(request.uri.path)) {
      await _verifyOtp(request);
      return;
    }

    if (request.method == 'POST' && _isDonationPath(request.uri.path)) {
      await _createDonationPayment(request);
      return;
    }

    if (request.method == 'POST' && _isPushPath(request.uri.path)) {
      await _handleMatrixPush(request);
      return;
    }

    await _json(request, HttpStatus.notFound, {'error': 'Not found'});
  } catch (e, st) {
    stderr.writeln('Request failed: $e\n$st');
    await _json(
      request,
      HttpStatus.internalServerError,
      {'error': 'Internal server error'},
    );
  }
}

bool _isSendPath(String path) =>
    path == '/' || path == '/send' || path == '/auth/otp/send';

bool _isVerifyPath(String path) =>
    path == '/verify' || path == '/auth/otp/verify';

bool _isDonationPath(String path) =>
    path == '/donations/create' ||
    path == '/auth/donations/create' ||
    path == '/auth/otp/donations/create';

bool _isPushPath(String path) =>
    path == '/push' ||
    path == '/auth/otp/push' ||
    path == '/_matrix/push/v1/notify' ||
    path == '/auth/push/_matrix/push/v1/notify' ||
    path == '/auth/otp/_matrix/push/v1/notify';

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
  final body =
      _notificationBody(notification, content, eventType, msgType, isCall);

  final data = <String, String>{
    'title': title,
    'body': body,
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
  };

  if (isCall) {
    data['type'] = 'm.call';
    data['call_type'] = _callType(eventType, msgType, content);
    final callId = content['call_id'] ?? content['id'];
    if (callId != null) data['call_id'] = callId.toString();
  }

  return _FcmPayload(data: data, isCall: isCall);
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
  if (contentBody != null && _isDisplayablePushText(contentBody)) {
    return contentBody;
  }

  final lowerEventType = eventType.toLowerCase();
  final lowerMsgType = msgType.toLowerCase();
  if (lowerEventType.contains('encrypted')) return 'New encrypted message';
  if (lowerMsgType.contains('image')) return 'Photo';
  if (lowerMsgType.contains('video')) return 'Video';
  if (lowerMsgType.contains('audio')) return 'Audio';
  if (lowerMsgType.contains('file')) return 'File';
  if (lowerMsgType.contains('location')) return 'Location';
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

bool _isCallNotification(
  String eventType,
  String msgType,
  Map<String, dynamic> content,
) {
  final lowerEventType = eventType.toLowerCase();
  final lowerContentType = content['type']?.toString().toLowerCase() ?? '';
  final lowerMsgType = msgType.toLowerCase();

  if (lowerEventType.startsWith('m.call.') ||
      lowerContentType.startsWith('m.call.')) {
    return true;
  }

  final hasCallId = content['call_id'] != null || content['id'] != null;
  final hasCallOfferOrAnswer =
      content['offer'] != null || content['answer'] != null;
  return hasCallId && hasCallOfferOrAnswer && !lowerMsgType.startsWith('m.');
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
  final content = await utf8.decoder.bind(request).join();
  if (content.trim().isEmpty) return {};
  return jsonDecode(content) as Map<String, dynamic>;
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
