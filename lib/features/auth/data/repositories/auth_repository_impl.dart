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
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final appMeta = user.appMetadata;
    final fullName =
        (meta['full_name'] as String?) ?? (meta['name'] as String?);
    final avatar =
        (meta['avatar_url'] as String?) ?? (meta['picture'] as String?);
    final provider = appMeta['provider'] as String?;
    final emailVerifiedRaw = meta['email_verified'];
    final emailVerified = emailVerifiedRaw is bool
        ? emailVerifiedRaw
        : emailVerifiedRaw is String
        ? emailVerifiedRaw.toLowerCase() == 'true'
        : false;
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      displayName: fullName ?? user.email,
      fullName: fullName,
      givenName: meta['given_name'] as String?,
      familyName: meta['family_name'] as String?,
      avatarUrl: avatar,
      provider: provider,
      locale: meta['locale'] as String?,
      emailVerified: emailVerified,
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
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
