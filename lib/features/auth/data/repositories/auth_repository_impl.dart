import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

const String _mobileRedirect = 'io.imdav.chepia.learning://login-callback';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  String get _oauthRedirect => kIsWeb ? Uri.base.origin : _mobileRedirect;

  AppUser? _mapUser(User? user) {
    if (user == null) return null;
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      displayName:
          user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String?,
    );
  }

  @override
  AppUser? get currentUser => _mapUser(_client.auth.currentUser);

  @override
  Stream<AppUser?> authStateChanges() {
    return _client.auth.onAuthStateChange.map(
      (event) => _mapUser(event.session?.user),
    );
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final mapped = _mapUser(res.user);
      if (mapped == null) throw const AuthFailure('No se pudo iniciar sesión');
      return mapped;
    } on AuthException catch (e, st) {
      AppLogger.warn('signInWithEmail failed', e, st);
      throw AuthFailure(e.message, cause: e);
    } catch (e, st) {
      AppLogger.error('signInWithEmail unknown', e, st);
      throw UnknownFailure('No se pudo iniciar sesión', e);
    }
  }

  @override
  Future<AppUser> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signUp(email: email, password: password);
      final mapped = _mapUser(res.user);
      if (mapped == null) throw const AuthFailure('No se pudo crear la cuenta');
      return mapped;
    } on AuthException catch (e, st) {
      AppLogger.warn('signUpWithEmail failed', e, st);
      throw AuthFailure(e.message, cause: e);
    } catch (e, st) {
      AppLogger.error('signUpWithEmail unknown', e, st);
      throw UnknownFailure('No se pudo crear la cuenta', e);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _oauthRedirect,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } on AuthException catch (e, st) {
      AppLogger.warn('signInWithGoogle failed', e, st);
      throw AuthFailure(e.message, cause: e);
    } catch (e, st) {
      AppLogger.error('signInWithGoogle unknown', e, st);
      throw UnknownFailure('No se pudo iniciar sesión con Google', e);
    }
  }

  @override
  Future<void> signInWithApple() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: _oauthRedirect,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } on AuthException catch (e, st) {
      AppLogger.warn('signInWithApple failed', e, st);
      throw AuthFailure(e.message, cause: e);
    } catch (e, st) {
      AppLogger.error('signInWithApple unknown', e, st);
      throw UnknownFailure('No se pudo iniciar sesión con Apple', e);
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }
}
