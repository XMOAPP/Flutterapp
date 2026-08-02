import 'dart:convert';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';
import '../firebase_options.dart';
import 'app_settings_service.dart';
import 'matrix_service.dart';
import 'voip_service.dart';

/// The normalized routing information carried by an XMO push notification.
/// Matrix gateways have historically used both snake_case and camelCase keys,
/// so this keeps every notification entry point on the same contract.
class PushNotificationRoute {
  const PushNotificationRoute(this.data);

  final Map<String, String> data;

  String? get roomId => _firstValue(const ['room_id', 'roomId', 'room']);
  String? get eventId => _firstValue(const ['event_id', 'eventId', 'event']);
  String? get callId => _firstValue(const [
        'call_id',
        'callId',
        'm.call.id',
        'm.call_id',
        'group_call_id',
        'groupCallId',
      ]);
  String? get callType => _firstValue(const [
        'call_type',
        'callType',
        'm.type',
        'm.call.type',
        'xmo_call_type',
        'xmo_call_kind',
      ]);
  bool get isGroupCall =>
      _truthy(data['group_call']) ||
      _firstValue(const ['group_call_id', 'groupCallId']) != null ||
      callType == 'group';
  String? get sender =>
      _firstValue(const ['sender_display_name', 'sender', 'room_name']);

  bool get isCall {
    if (data['xmo_push_type']?.toLowerCase() == 'call') return true;
    final eventType = (data['event_type'] ?? data['type'] ?? '').toLowerCase();
    if (eventType.startsWith('m.call.') ||
        eventType == 'org.matrix.msc3401.call' ||
        eventType == 'org.matrix.msc3401.call.member') {
      return true;
    }
    return callId != null &&
        (isGroupCall ||
            data.containsKey('offer') ||
            data.containsKey('answer'));
  }

  String? _firstValue(List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  bool _truthy(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;
    }
    return false;
  }
}

@pragma('vm:entry-point')
Future<void> xmoFirebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase can already be initialized when the background isolate starts.
  }
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static const _messagesChannel = AndroidNotificationChannel(
    'xmo_messages_v2',
    'XMO messages',
    description: 'Message notifications from XMO chats',
    importance: Importance.defaultImportance,
  );

  static const _callsChannel = AndroidNotificationChannel(
    'xmo_call_alerts_v2',
    'XMO calls',
    description: 'Incoming voice and video call notifications from XMO',
    importance: Importance.high,
  );

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _nativeCallMethods = MethodChannel(
    'com.xmo.xmo/call_notifications',
  );
  static const EventChannel _nativeCallEvents = EventChannel(
    'com.xmo.xmo/call_notification_events',
  );
  static const MethodChannel _nativeNotificationMethods = MethodChannel(
    'com.xmo.xmo/notification_navigation',
  );
  static const EventChannel _nativeNotificationEvents = EventChannel(
    'com.xmo.xmo/notification_navigation_events',
  );

  MatrixService? _matrixService;
  bool _initialized = false;
  bool _localNotificationsReady = false;
  StreamSubscription? _nativeCallActionsSub;
  StreamSubscription? _nativeNotificationActionsSub;
  String? _registeredToken;
  Future<void> Function(PushNotificationRoute route)? _onOpenChat;

  Future<void> init({
    required MatrixService matrixService,
    Future<void> Function(PushNotificationRoute route)? onOpenChat,
  }) async {
    _matrixService = matrixService;
    _onOpenChat = onOpenChat ?? _onOpenChat;
    if (_initialized) {
      await registerCurrentUser();
      return;
    }

    _initialized = true;
    FirebaseMessaging.onBackgroundMessage(
      xmoFirebaseMessagingBackgroundHandler,
    );

    try {
      await _requestPermission();
      await _initLocalNotifications();

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
      _messaging.onTokenRefresh.listen((_) {
        registerCurrentUser();
      });
      await _initNativeCallActions();
      await _initNativeNotificationNavigation();
      await _handleInitialNotificationLaunch();

      await registerCurrentUser();
    } catch (e) {
      debugPrint('[PushNotificationService] Push init skipped: $e');
    }
  }

  Future<void> _initNativeCallActions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_nativeCallActionsSub != null) return;

    try {
      final initial = await _nativeCallMethods.invokeMethod<dynamic>(
        'initialCallAction',
      );
      if (initial is Map) {
        unawaited(_handleNativeCallAction(initial));
      }
    } catch (e) {
      debugPrint(
          '[PushNotificationService] Native call action init failed: $e');
    }

    _nativeCallActionsSub =
        _nativeCallEvents.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        unawaited(_handleNativeCallAction(event));
      }
    }, onError: (Object e) {
      debugPrint(
          '[PushNotificationService] Native call action stream failed: $e');
    });
  }

  Future<bool> canUseFullScreenCallAlerts() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _nativeCallMethods.invokeMethod<bool>(
            'canUseFullScreenIntent',
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint(
        '[PushNotificationService] Full-screen call status failed: ${e.code}',
      );
      return false;
    }
  }

  Future<bool> openFullScreenCallAlertSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _nativeCallMethods.invokeMethod<bool>(
            'openFullScreenIntentSettings',
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint(
        '[PushNotificationService] Could not open call alert settings: ${e.code}',
      );
      return false;
    }
  }

  Future<void> _handleNativeCallAction(Map<dynamic, dynamic> payload) async {
    final normalized = payload.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
    debugPrint('[PushNotificationService] Native call action: $normalized');
    await VoipService().handleNativeCallNotificationAction(normalized);
  }

  Future<void> _initNativeNotificationNavigation() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_nativeNotificationActionsSub != null) return;

    try {
      final initial = await _nativeNotificationMethods.invokeMethod<dynamic>(
        'initialNotificationPayload',
      );
      if (initial is Map) {
        unawaited(_routePayload(_normalizePayload(initial)));
      }
    } catch (e) {
      debugPrint(
        '[PushNotificationService] Native notification navigation init failed: $e',
      );
    }

    _nativeNotificationActionsSub =
        _nativeNotificationEvents.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        unawaited(_routePayload(_normalizePayload(event)));
      }
    }, onError: (Object e) {
      debugPrint(
        '[PushNotificationService] Native notification navigation stream failed: $e',
      );
    });
  }

  Future<void> _handleInitialNotificationLaunch() async {
    final remote = await _messaging.getInitialMessage();
    if (remote != null) {
      unawaited(_routePayload(PushNotificationRoute(remote.data.map(
        (key, value) => MapEntry(key, value.toString()),
      ))));
    }

    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        response?.payload != null) {
      _handleNotificationResponse(response!);
    }
  }

  PushNotificationRoute _normalizePayload(Map<dynamic, dynamic> payload) {
    return PushNotificationRoute(payload.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    ));
  }

  Future<void> _routePayload(
    PushNotificationRoute route, {
    String action = 'open',
  }) async {
    if (route.isCall) {
      final payload = <String, String>{...route.data, 'xmo_action': action};
      await VoipService().handleNativeCallNotificationAction(payload);
      return;
    }

    final roomId = route.roomId;
    if (roomId == null || roomId.isEmpty) {
      debugPrint(
          '[PushNotificationService] Notification has no room id: ${route.data}');
      return;
    }
    final handler = _onOpenChat;
    if (handler == null) {
      debugPrint('[PushNotificationService] Chat navigation is not ready yet.');
      return;
    }
    await handler(route);
  }

  Future<void> registerCurrentUser() async {
    final service = _matrixService;
    if (service == null || !service.isLoggedIn) {
      debugPrint(
        '[PushNotificationService] Pusher registration skipped: '
        'XMO user is not logged in.',
      );
      return;
    }

    final settings = await AppSettingsService().load();
    if (!settings.notificationsEnabled) {
      debugPrint(
        '[PushNotificationService] Notifications disabled; removing pusher.',
      );
      await unregisterCurrentUser();
      return;
    }

    final gatewayUrl = AppConfig.pushGatewayUrl.trim();
    if (gatewayUrl.isEmpty) {
      debugPrint(
        '[PushNotificationService] XMO_PUSH_GATEWAY_URL is empty; '
        'skipping push registration.',
      );
      return;
    }

    final token = await _getFcmToken();
    if (token == null || token.isEmpty) return;

    try {
      debugPrint(
        '[PushNotificationService] Registering XMO push endpoint: '
        'user=${service.userId}, gateway=$gatewayUrl, '
        'token=${_redactToken(token)}',
      );
      await service.setHttpPusher(
        pushKey: token,
        appId: AppConfig.pushAppId,
        appDisplayName: 'XMO',
        deviceDisplayName: _deviceDisplayName,
        profileTag: AppConfig.pushProfileTag,
        pushGatewayUrl: gatewayUrl,
      );
      _registeredToken = token;
      debugPrint('[PushNotificationService] XMO push endpoint registered.');
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to register pusher: $e');
    }
  }

  Future<void> unregisterCurrentUser() async {
    final service = _matrixService;
    if (service == null || !service.isLoggedIn) {
      debugPrint(
        '[PushNotificationService] Pusher removal skipped: '
        'XMO user is not logged in.',
      );
      return;
    }

    final token = _registeredToken ?? await _getFcmToken();
    if (token == null || token.isEmpty) {
      debugPrint(
        '[PushNotificationService] Pusher removal skipped: no FCM token.',
      );
      return;
    }

    try {
      await service.removeHttpPusher(
        pushKey: token,
        appId: AppConfig.pushAppId,
      );
      _registeredToken = null;
      debugPrint('[PushNotificationService] XMO push endpoint removed.');
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to remove pusher: $e');
    }
  }

  Future<void> _requestPermission() async {
    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('[PushNotificationService] Permission request failed: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    if (_localNotificationsReady || kIsWeb) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _localNotifications.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );

      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_messagesChannel);
      await android?.createNotificationChannel(_callsChannel);
      await android?.requestNotificationsPermission();

      _localNotificationsReady = true;
    } catch (e) {
      debugPrint(
        '[PushNotificationService] Local notification init failed: $e',
      );
    }
  }

  Future<String?> _getFcmToken() async {
    try {
      final token = await _messaging.getToken();
      debugPrint(
        '[PushNotificationService] FCM token: ${_redactToken(token)}',
      );
      return token;
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to read FCM token: $e');
      return null;
    }
  }

  String _redactToken(String? token) {
    if (token == null || token.isEmpty) return '<empty>';
    if (token.length <= 12) return '<short:${token.length}>';
    return '${token.substring(0, 6)}...${token.substring(token.length - 6)}';
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final settings = await AppSettingsService().load();
    if (!settings.notificationsEnabled || !_localNotificationsReady) return;

    final isCall = _looksLikeCall(message);
    final title = _notificationTitle(message, isCall);
    final body = _notificationBody(message, isCall);
    if (title.isEmpty && body.isEmpty) return;

    await _localNotifications.show(
      id: _notificationId(message),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          isCall ? _callsChannel.id : _messagesChannel.id,
          isCall ? _callsChannel.name : _messagesChannel.name,
          channelDescription:
              isCall ? _callsChannel.description : _messagesChannel.description,
          importance: isCall ? Importance.high : Importance.defaultImportance,
          priority: isCall ? Priority.high : Priority.defaultPriority,
          category: isCall
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          actions: isCall
              ? const <AndroidNotificationAction>[
                  AndroidNotificationAction(
                    'decline',
                    'Decline',
                    cancelNotification: true,
                  ),
                  AndroidNotificationAction(
                    'answer',
                    'Answer',
                    showsUserInterface: true,
                    cancelNotification: true,
                  ),
                ]
              : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    debugPrint(
      '[PushNotificationService] Notification opened: ${message.data}',
    );
    unawaited(_routePayload(PushNotificationRoute(message.data.map(
      (key, value) => MapEntry(key, value.toString()),
    ))));
  }

  void _handleNotificationResponse(NotificationResponse response) {
    debugPrint(
      '[PushNotificationService] Local notification opened: '
      '${response.payload}',
    );
    final rawPayload = response.payload;
    if (rawPayload == null || rawPayload.isEmpty) return;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map) return;
      unawaited(
        _routePayload(
          _normalizePayload(decoded),
          action: (response.actionId?.isEmpty ?? true)
              ? 'open'
              : response.actionId!,
        ),
      );
    } catch (e) {
      debugPrint('[PushNotificationService] Invalid notification payload: $e');
    }
  }

  bool _looksLikeCall(RemoteMessage message) {
    if (message.data['xmo_push_type'] == 'call') return true;
    final eventType = (message.data['event_type'] ?? message.data['type'] ?? '')
        .toString()
        .toLowerCase();
    if (eventType.startsWith('m.call.') || _isGroupCallEventType(eventType)) {
      return true;
    }
    final msgType =
        (message.data['msgtype'] ?? message.data['message_type'] ?? '')
            .toString()
            .toLowerCase();
    final groupCallType =
        (message.data['m.type'] ?? message.data['call_type'] ?? '')
            .toString()
            .toLowerCase();
    final groupCallIntent =
        (message.data['m.intent'] ?? message.data['call_intent'] ?? '')
            .toString()
            .toLowerCase();
    if ((groupCallType == 'm.voice' || groupCallType == 'm.video') &&
        (groupCallIntent == 'm.ring' ||
            groupCallIntent == 'm.prompt' ||
            groupCallIntent == 'm.room')) {
      return true;
    }
    final hasCallId = _hasAnyKey(message.data, const [
      'call_id',
      'callId',
      'm.call.id',
      'm.call_id',
      'group_call_id',
      'groupCallId',
    ]);
    final hasCallPayload =
        message.data.containsKey('offer') || message.data.containsKey('answer');
    final isGroupCall = _truthy(message.data['group_call']?.toString()) ||
        message.data.containsKey('group_call_id') ||
        message.data.containsKey('groupCallId');
    return hasCallId &&
        (hasCallPayload || isGroupCall) &&
        !msgType.startsWith('m.');
  }

  bool _isGroupCallEventType(String eventType) {
    return eventType == 'org.matrix.msc3401.call' ||
        eventType == 'org.matrix.msc3401.call.member';
  }

  String _notificationTitle(RemoteMessage message, bool isCall) {
    final title = message.notification?.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final dataTitle = message.data['title']?.toString().trim();
    if (dataTitle != null && dataTitle.isNotEmpty) return dataTitle;
    final sender = message.data['sender_display_name'] ??
        message.data['sender'] ??
        message.data['room_name'];
    if (sender != null && sender.toString().trim().isNotEmpty) {
      return sender.toString();
    }
    return isCall ? 'Incoming call' : 'New message';
  }

  String _notificationBody(RemoteMessage message, bool isCall) {
    final previewLabel = message.data['preview_label']?.toString().trim();
    final previewKind = message.data['preview_kind']?.toString().trim();
    if (previewLabel != null &&
        previewLabel.isNotEmpty &&
        previewKind != null &&
        previewKind.isNotEmpty) {
      if (previewKind.toLowerCase() == 'encrypted') {
        return 'New message';
      }
      final genericRoomUpdate = previewKind.toLowerCase() == 'room' &&
          previewLabel.toLowerCase() == 'room updated';
      if (!genericRoomUpdate) {
        return '${_previewPrefix(previewKind)}$previewLabel';
      }
    }

    final dataBody = message.data['body']?.toString().trim();
    final eventType =
        (message.data['event_type'] ?? message.data['msgtype'] ?? '')
            .toString()
            .toLowerCase();
    final msgType =
        (message.data['msgtype'] ?? message.data['message_type'] ?? '')
            .toString()
            .toLowerCase();
    if (eventType.contains('encrypted')) {
      return 'New message';
    }
    if (msgType.contains('image')) return '🖼️ Photo';
    if (msgType.contains('video')) return '▶ Video';
    if (msgType.contains('audio')) {
      final fileName = (message.data['filename'] ??
              message.data['content'] ??
              message.data['body'])
          ?.toString()
          .trim();
      if (fileName != null && fileName.toLowerCase().startsWith('voice_')) {
        return '🎙 Voice message';
      }
      final label = fileName != null && _isDisplayablePushText(fileName)
          ? fileName
          : 'Audio';
      return '🎧 $label';
    }
    if (msgType.contains('file')) {
      final fileName = (message.data['filename'] ??
              message.data['content'] ??
              message.data['body'])
          ?.toString()
          .trim();
      final label = fileName != null && _isDisplayablePushText(fileName)
          ? fileName
          : 'File';
      return '${_previewPrefix(message.data['preview_kind'] ?? 'file')}$label';
    }
    if (msgType.contains('location')) return '📍 Location';
    final body = message.notification?.body?.trim();
    if (body != null && _isDisplayablePushText(body)) return body;
    if (dataBody != null && _isDisplayablePushText(dataBody)) {
      return dataBody;
    }
    final content = message.data['content'] ??
        message.data['body'] ??
        message.data['event_type'];
    final contentText = content?.toString().trim();
    if (contentText != null && _isDisplayablePushText(contentText)) {
      return contentText;
    }
    if (eventType.startsWith('m.room.')) return 'Room updated';
    return isCall ? 'Tap to open XMO' : 'Open XMO to view this message';
  }

  String _previewPrefix(String kind) {
    switch (kind.toLowerCase()) {
      case 'image':
        return '🖼️ ';
      case 'video':
        return '▶ ';
      case 'voice':
        return '🎙 ';
      case 'audio':
        return '🎧 ';
      case 'spreadsheet':
        return '📊 ';
      case 'location':
        return '📍 ';
      case 'encrypted':
        return '🔒 ';
      case 'pdf':
        return '📄 ';
      case 'word':
        return '📝 ';
      case 'presentation':
        return '📊 ';
      case 'apk':
      case 'archive':
      case 'app':
        return '📦 ';
      case 'text_file':
        return '📄 ';
      case 'code':
        return '💻 ';
      case 'file':
        return '📄 ';
      default:
        return '';
    }
  }

  bool _isDisplayablePushText(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    if (value.startsWith('m.call.') || value.startsWith('m.room.')) {
      return false;
    }
    return true;
  }

  int _notificationId(RemoteMessage message) {
    final isCall = _looksLikeCall(message);
    final seed = isCall
        ? message.data['call_id']?.toString() ??
            message.data['callId']?.toString() ??
            message.data['group_call_id']?.toString() ??
            message.data['groupCallId']?.toString() ??
            message.data['event_id']?.toString() ??
            message.data['eventId']?.toString() ??
            message.messageId ??
            message.sentTime?.millisecondsSinceEpoch.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString()
        : message.messageId ??
            message.data['event_id']?.toString() ??
            message.data['eventId']?.toString() ??
            message.data['room_id']?.toString() ??
            message.data['roomId']?.toString() ??
            message.sentTime?.millisecondsSinceEpoch.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString();
    return seed.hashCode & 0x7fffffff;
  }

  bool _hasAnyKey(Map<String, dynamic> data, List<String> keys) {
    return keys.any(data.containsKey);
  }

  bool _truthy(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;
    }
    return false;
  }

  String get _deviceDisplayName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'XMO Android';
      case TargetPlatform.iOS:
        return 'XMO iPhone';
      case TargetPlatform.macOS:
        return 'XMO macOS';
      case TargetPlatform.windows:
        return 'XMO Windows';
      case TargetPlatform.linux:
        return 'XMO Linux';
      case TargetPlatform.fuchsia:
        return 'XMO mobile';
    }
  }
}
