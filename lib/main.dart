import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  runApp(const GokulaInventoryApp());
}

class GokulaInventoryApp extends StatelessWidget {
  const GokulaInventoryApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4F72)), useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
