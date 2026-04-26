import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'providers/chat_filter_provider.dart';
import 'providers/matrix_provider.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Matrix SDK before app starts
  final matrixProvider = MatrixProvider();
  await matrixProvider.init();

  runApp(XmoApp(matrixProvider: matrixProvider));
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
      ],
      child: MaterialApp(
        title: 'xmo',
        debugShowCheckedModeBanner: false,
        theme: buildXmoTheme(),
        home: const SplashScreen(),
      ),
    );
  }
}
