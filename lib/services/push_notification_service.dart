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
    'xmo_messages',
    'XMO messages',
    description: 'Message notifications from XMO chats',
    importance: Importance.high,
  );

  static const _callsChannel = AndroidNotificationChannel(
    'xmo_call_alerts',
    'XMO calls',
    description: 'Incoming voice and video call notifications from XMO',
    importance: Importance.max,
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

  MatrixService? _matrixService;
  bool _initialized = false;
  bool _localNotificationsReady = false;
  StreamSubscription? _nativeCallActionsSub;
  String? _registeredToken;

  Future<void> init({required MatrixService matrixService}) async {
    _matrixService = matrixService;
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

  Future<void> _handleNativeCallAction(Map<dynamic, dynamic> payload) async {
    final normalized = payload.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
    debugPrint('[PushNotificationService] Native call action: $normalized');
    await VoipService().handleNativeCallNotificationAction(normalized);
  }

  Future<void> registerCurrentUser() async {
    final service = _matrixService;
    if (service == null || !service.isLoggedIn) {
      debugPrint(
        '[PushNotificationService] Pusher registration skipped: '
        'Matrix user is not logged in.',
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
        'skipping Matrix pusher registration.',
      );
      return;
    }

    final token = await _getFcmToken();
    if (token == null || token.isEmpty) return;

    try {
      debugPrint(
        '[PushNotificationService] Registering Matrix pusher: '
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
      debugPrint('[PushNotificationService] Matrix pusher registered.');
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to register pusher: $e');
    }
  }

  Future<void> unregisterCurrentUser() async {
    final service = _matrixService;
    if (service == null || !service.isLoggedIn) {
      debugPrint(
        '[PushNotificationService] Pusher removal skipped: '
        'Matrix user is not logged in.',
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
      debugPrint('[PushNotificationService] Matrix pusher removed.');
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
          importance: isCall ? Importance.max : Importance.high,
          priority: isCall ? Priority.max : Priority.high,
          category: isCall
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
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
  }

  void _handleNotificationResponse(NotificationResponse response) {
    debugPrint(
      '[PushNotificationService] Local notification opened: '
      '${response.payload}',
    );
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
    final hasCallId = message.data.containsKey('call_id') ||
        message.data.containsKey('m.call.id');
    final hasCallPayload =
        message.data.containsKey('offer') || message.data.containsKey('answer');
    return hasCallId && hasCallPayload && !msgType.startsWith('m.');
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
      return '${_previewPrefix(previewKind)}$previewLabel';
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
    if (eventType.contains('encrypted')) return '🔒 New encrypted message';
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
    if (eventType.startsWith('m.room.')) return 'Room updated';
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
    final seed = message.messageId ??
        message.data['event_id']?.toString() ??
        message.sentTime?.millisecondsSinceEpoch.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return seed.hashCode & 0x7fffffff;
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
