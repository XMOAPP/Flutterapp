import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:reown_appkit/reown_appkit.dart';
import '../theme.dart';
import 'core/app_dependencies.dart';
import '../providers/chat_filter_provider.dart';
import '../providers/matrix_provider.dart';
import '../providers/group_provider.dart';
import '../providers/story_provider.dart';
import '../services/app_lock_service.dart';
import '../services/call_link_service.dart';
import '../services/crash_reporting_service.dart';
import '../services/push_notification_service.dart';
import '../services/story_service.dart';
import '../services/voip_service.dart';
import '../services/wallet_deep_link_handler.dart';
import 'screens/direct_chat/call_pip_overlay.dart';
import 'screens/direct_chat/incoming_call_banner.dart';
import 'screens/matrix_chat_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/connection_status_banner.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

final xmoNavigatorKey = GlobalKey<NavigatorState>();
String? _lastPushRouteKey;
DateTime? _lastPushRouteAt;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CallLinkService.instance.init(navigatorKey: xmoNavigatorKey);
  WalletDeepLinkHandler.initListener();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final matrixProvider = MatrixProvider();
  runApp(XmoApp(matrixProvider: matrixProvider));
  unawaited(
    _bootstrapServices(matrixProvider)
        .catchError((Object error, StackTrace stack) {
      debugPrint('[main] Startup bootstrap failed: $error');
      debugPrintStack(stackTrace: stack);
    }),
  );
}

Future<void> _bootstrapServices(MatrixProvider matrixProvider) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await CrashReportingService.initialize();
  } catch (e) {
    debugPrint("Firebase init failed (expected if not configured yet): $e");
  }

  await matrixProvider.init(
    beforeStartSync: () {
      VoipService().init(
        matrixService: matrixProvider.service,
        navigatorKey: xmoNavigatorKey,
      );
    },
  );
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
            title: 'xmo',
            debugShowCheckedModeBanner: false,
            theme: buildXmoTheme(),
            home: const SplashScreen(),
            // ── PiP overlay sits on top of all routes ──────────────────────
            builder: (context, child) {
              return AppLockGate(
                child: Stack(
                  children: [
                    child!,
                    const ConnectionStatusBanner(),
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
              );
            },
          ),
        ),
      ),
    );
  }
}
