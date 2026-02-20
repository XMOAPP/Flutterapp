import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'providers/chat_filter_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const XmoApp());
}

class XmoApp extends StatelessWidget {
  const XmoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ChatFilterProvider())],
      child: MaterialApp(
        title: 'xmo',
        debugShowCheckedModeBanner: false,
        theme: buildXmoTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}
