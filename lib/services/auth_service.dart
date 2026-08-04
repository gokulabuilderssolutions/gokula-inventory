import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Sign up failed. Please try again.');
    }

    // Insert into profiles table (if not already present via trigger).
    await _supabase.from('profiles').upsert({
      'id': user.id,
      'email': email.trim(),
      'full_name': fullName.trim(),
      'role': 'user',
      'is_active': true,
    });

    return {
      'id': user.id,
      'email': email.trim(),
      'full_name': fullName.trim(),
      'role': 'user',
      'is_active': true,
    };
  }

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

  Future<void> logout() => _supabase.auth.signOut();

  User? get currentUser => _supabase.auth.currentUser;

  bool get isLoggedIn => currentUser != null;
}
