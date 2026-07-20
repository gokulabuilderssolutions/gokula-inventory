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
      throw Exception('Login failed. User not found.');
    }

    final profile = await _supabase
        .from('profiles')
        .select('id, email, full_name, role, is_active')
        .eq('id', user.id)
        .single();

    if (profile['is_active'] != true) {
      await _supabase.auth.signOut();
      throw Exception('Your account is inactive. Contact the administrator.');
    }

    return Map<String, dynamic>.from(profile);
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
  }

  User? get currentUser => _supabase.auth.currentUser;

  bool get isLoggedIn => currentUser != null;
}