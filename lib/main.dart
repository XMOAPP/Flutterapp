import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:reown_appkit/reown_appkit.dart';
import '../theme.dart';
import 'core/app_dependencies.dart';
import '../models/story_models.dart';
import '../providers/chat_filter_provider.dart';
import '../providers/matrix_provider.dart';
import '../providers/group_provider.dart';
import '../providers/story_provider.dart';
import '../services/app_lock_service.dart';
import '../services/account_deletion_completion_service.dart';
import '../services/call_link_service.dart';
import '../services/crash_reporting_service.dart';
import '../services/device_verification_coordinator.dart';
import '../services/invite_link_service.dart';
import '../services/matrix_service.dart';
import '../services/matrix_sso_service.dart';
import '../services/push_notification_service.dart';
import '../services/streaming_media_service.dart';
import '../services/story_service.dart';
import '../services/story_upload_queue_service.dart';
import '../services/voip_service.dart';
import '../services/wallet_deep_link_handler.dart';
import '../services/visible_chat_route_service.dart';
import 'screens/direct_chat/call_pip_overlay.dart';
import 'screens/direct_chat/incoming_call_banner.dart';
import 'screens/matrix_chat_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/connection_status_banner.dart';
import 'widgets/global_transfer_indicator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';

final xmoNavigatorKey = GlobalKey<NavigatorState>();
String? _lastPushRouteKey;
DateTime? _lastPushRouteAt;
StreamSubscription<Story>? _storyUploadCompletionSubscription;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    final configurationErrors = AppConfig.productionConfigurationErrors();
    if (configurationErrors.isNotEmpty) {
      throw StateError(
        'Invalid XMO production configuration: '
        '${configurationErrors.join('; ')}',
      );
    }
  }
  CallLinkService.instance.init(navigatorKey: xmoNavigatorKey);
  WalletDeepLinkHandler.initListener();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final matrixProvider = MatrixProvider(
    onAuthenticatedSessionReady: () {
      VoipService().init(
        matrixService: MatrixService(),
        navigatorKey: xmoNavigatorKey,
      );
    },
  );
  AccountDeletionCompletionService.instance.init(
    navigatorKey: xmoNavigatorKey,
    matrixProvider: matrixProvider,
  );
  InviteLinkService.instance.init(
    navigatorKey: xmoNavigatorKey,
    matrixProvider: matrixProvider,
  );
  runApp(XmoApp(matrixProvider: matrixProvider));
  unawaited(
    _bootstrapServices(matrixProvider).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('[main] Startup bootstrap failed: $error');
      debugPrintStack(stackTrace: stack);
    }),
  );
}

Future<void> _bootstrapServices(MatrixProvider matrixProvider) async {
  try {
    await StreamingMediaService.cleanupDefaultCache();
  } catch (e, stack) {
    debugPrint('[main] Streaming media cache cleanup skipped: $e');
    debugPrintStack(stackTrace: stack);
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await CrashReportingService.initialize();
  } catch (e) {
    debugPrint("Firebase init failed (expected if not configured yet): $e");
  }

  await matrixProvider.init();
  if (matrixProvider.state == MatrixAuthState.error) {
    debugPrint(
      '[main] Matrix startup stopped before dependent services: '
      '${matrixProvider.error}',
    );
    return;
  }
  MatrixSsoService.instance.setRecoveredTokenHandler(
    matrixProvider.loginWithSsoToken,
  );
  await DeviceVerificationCoordinator.instance.init(
    navigatorKey: xmoNavigatorKey,
    matrixProvider: matrixProvider,
  );
  await AccountDeletionCompletionService.instance.checkCurrentSession();
  try {
    await _storyUploadCompletionSubscription?.cancel();
    _storyUploadCompletionSubscription = StoryUploadQueueService
        .instance
        .completedStories
        .listen((_) => _showStoryUploadCompleted());
    await StoryUploadQueueService.instance.attach(
      StoryService(matrixProvider.service),
    );
  } catch (e, stack) {
    debugPrint('[main] Story upload recovery skipped: $e');
    debugPrintStack(stackTrace: stack);
  }
  try {
    await PushNotificationService().init(
      matrixService: matrixProvider.service,
      onOpenChat: (route) => _openPushChat(matrixProvider, route),
    );
  } catch (e, stack) {
    debugPrint('[main] Push notification startup skipped: $e');
    debugPrintStack(stackTrace: stack);
  }

  try {
    await WalletDeepLinkHandler.checkInitialLink();
  } catch (e, stack) {
    debugPrint('[main] Initial deep link handling skipped: $e');
    debugPrintStack(stackTrace: stack);
  }
}

void _showStoryUploadCompleted() {
  final context = xmoNavigatorKey.currentContext;
  if (context == null) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text('Story uploaded successfully'),
      backgroundColor: kLimeGreen,
      duration: Duration(seconds: 2),
    ),
  );
}

Future<void> _openPushChat(
  MatrixProvider matrixProvider,
  PushNotificationRoute route,
) async {
  final roomId = route.roomId;
  if (roomId == null || roomId.isEmpty || !matrixProvider.isLoggedIn) return;

  final routeKey = '$roomId:${route.eventId ?? ''}';
  final lastRouteAt = _lastPushRouteAt;
  if (_lastPushRouteKey == routeKey &&
      lastRouteAt != null &&
      DateTime.now().difference(lastRouteAt) < const Duration(seconds: 2)) {
    return;
  }

  // A notification can open XMO before the first sync has populated rooms.
  // Refresh a few times instead of dropping the user's navigation request.
  var room = matrixProvider.service.getRoomById(roomId);
  for (var attempt = 0; room == null && attempt < 4; attempt++) {
    try {
      await matrixProvider.service.client.oneShotSync();
    } catch (e) {
      debugPrint('[main] Push room refresh failed: $e');
    }
    room = matrixProvider.service.getRoomById(roomId);
    if (room == null) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }
  if (room == null) {
    debugPrint('[main] Push room not available: $roomId');
    return;
  }

  final navigator = xmoNavigatorKey.currentState;
  if (navigator == null) return;
  _lastPushRouteKey = routeKey;
  _lastPushRouteAt = DateTime.now();
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => MatrixChatScreen(
        room: room,
        matrixProvider: matrixProvider,
        initialHighlightedEventId: route.eventId,
      ),
    ),
  );
}

class XmoApp extends StatelessWidget {
  final MatrixProvider matrixProvider;
  final AppDependencies dependencies;

  XmoApp({super.key, required this.matrixProvider})
    : dependencies = AppDependencies.from(matrixProvider.service);

  void _openUploadChat(String roomId) {
    if (VisibleChatRouteService.instance.roomId.value == roomId) return;
    final room = matrixProvider.service.getRoomById(roomId);
    final navigator = xmoNavigatorKey.currentState;
    if (room == null || navigator == null) return;
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              MatrixChatScreen(room: room, matrixProvider: matrixProvider),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatFilterProvider()),
        ChangeNotifierProvider.value(value: matrixProvider),
        ChangeNotifierProvider.value(value: AppLockService.instance),
        ChangeNotifierProvider(
          create: (_) => GroupProvider(matrixProvider.service),
        ),
        ChangeNotifierProvider(
          create: (_) => StoryProvider(StoryService(matrixProvider.service)),
        ),
      ],
      child: AppDependenciesScope(
        dependencies: dependencies,
        child: ReownAppKitModalTheme(
          isDarkMode: true,
          child: MaterialApp(
            navigatorKey: xmoNavigatorKey,
            navigatorObservers: [xmoRouteObserver],
            title: 'xmo',
            debugShowCheckedModeBanner: false,
            theme: buildXmoTheme(),
            home: const SplashScreen(),
            // ── PiP overlay sits on top of all routes ──────────────────────
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final clampedMediaQuery = mediaQuery.copyWith(
                textScaler: mediaQuery.textScaler.clamp(
                  minScaleFactor: 0.85,
                  maxScaleFactor: 1.0,
                ),
              );

              return MediaQuery(
                data: clampedMediaQuery,
                child: AppLockGate(
                  child: Stack(
                    children: [
                      child!,
                      const ConnectionStatusBanner(),
                      GlobalTransferIndicator(onOpenChat: _openUploadChat),
                      ValueListenableBuilder<bool>(
                        valueListenable: VoipService().pipMode,
                        builder: (_, isPip, __) {
                          if (!isPip) return const SizedBox.shrink();
                          return const CallPipOverlay();
                        },
                      ),
                      const IncomingCallBanner(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
