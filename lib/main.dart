import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/inventory_viewer_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const GokulaInventoryApp());
}

class GokulaInventoryApp extends StatelessWidget {
  const GokulaInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4F72),
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        return FutureBuilder<Map<String, dynamic>?>(
          key: ValueKey(session.user.id),
          future: AuthService().currentProfile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.hasError) {
              return const Scaffold(body: Center(child: Text('Unable to verify account permissions. Check connection.')));
            }
            if (!profileSnapshot.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final profile = profileSnapshot.data;
            if (profile == null || profile['is_active'] != true) {
              return const Scaffold(body: Center(child: Text('Account inactive or not configured. Please sign out and contact Admin.')));
            }
            final role = (profile['role'] ?? '').toString().toLowerCase();
            if (role == 'viewer' || role == 'inventory_viewer') return const InventoryViewerScreen();
            if (role == 'admin' || role == 'user') return const HomeScreen();
            return const Scaffold(body: Center(child: Text('Account role not recognized.')));
          },
        );
      },
    );
  }
}
