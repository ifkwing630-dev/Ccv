import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CcvApp());
}

class CcvApp extends StatelessWidget {
  const CcvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ccv',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      ),
      initialRoute: '/home',
      routes: {
        '/home': (_) => const HomeScreen(),
      },
    );
  }
}
