import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Login failed. Check your email and password.');
    }

    final profile = await _supabase
        .from('profiles')
        .select('id, email, full_name, role, is_active')
        .eq('id', user.id)
        .maybeSingle();

    if (profile == null) {
      await _supabase.auth.signOut();
      throw Exception('User profile is not configured. Contact the administrator.');
    }

    if (profile['is_active'] != true) {
      await _supabase.auth.signOut();
      throw Exception('Your account is inactive. Contact the administrator.');
    }

    return Map<String, dynamic>.from(profile);
  }

  Future<Map<String, dynamic>?> currentProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final profile = await _supabase
        .from('profiles')
        .select('id, email, full_name, role, is_active')
        .eq('id', user.id)
        .maybeSingle();

    if (profile == null) return null;
    return Map<String, dynamic>.from(profile);
  }

  Future<String> currentRole() async {
    final profile = await currentProfile();
    return (profile?['role'] ?? 'user').toString().toLowerCase();
  }

  Future<bool> isAdmin() async => (await currentRole()) == 'admin';

  Future<void> logout() => _supabase.auth.signOut();

  User? get currentUser => _supabase.auth.currentUser;

  bool get isLoggedIn => currentUser != null;
}
