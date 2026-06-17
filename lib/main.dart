import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:reown_appkit/reown_appkit.dart';
import '../theme.dart';
import '../providers/chat_filter_provider.dart';
import '../providers/matrix_provider.dart';
import '../providers/group_provider.dart';
import '../providers/story_provider.dart';
import '../services/app_lock_service.dart';
import '../services/call_link_service.dart';
import '../services/push_notification_service.dart';
import '../services/story_service.dart';
import '../services/voip_service.dart';
import '../services/wallet_deep_link_handler.dart';
import 'screens/direct_chat/call_pip_overlay.dart';
import 'screens/direct_chat/incoming_call_banner.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_lock_gate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

final xmoNavigatorKey = GlobalKey<NavigatorState>();

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

class XmoApp extends StatelessWidget {
  final MatrixProvider matrixProvider;
  const XmoApp({super.key, required this.matrixProvider});

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
    );
  }
}
