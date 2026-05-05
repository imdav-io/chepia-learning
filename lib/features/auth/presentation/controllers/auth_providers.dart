import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

final authStateProvider = StreamProvider<AppUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges();
});

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Indica si Supabase ya intentó restaurar la sesión persistida.
///
/// El router NO debe redirigir fuera de `/splash` mientras este provider
/// no tenga valor: en iOS/Android `flutter_secure_storage` es asíncrono y
/// en web los OAuth callbacks llegan con el token en el fragment, así que
/// `currentUser` puede ser null por unos cientos de ms aunque sí haya sesión.
///
/// Resuelve a `true` cuando:
///   1. ya existe `currentUser` (sesión restaurada al `await Supabase.initialize`), o
///   2. llegó la primera emisión de `onAuthStateChange`, o
///   3. pasaron 1.5 s y asumimos que no hay sesión.
final authBootstrapProvider = FutureProvider<bool>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  if (repo.currentUser != null) return true;
  try {
    await repo
        .authStateChanges()
        .firstWhere((u) => u != null)
        .timeout(const Duration(milliseconds: 1500));
  } catch (_) {
    // Timeout o stream cerrado: no hay sesión persistida, seguimos.
  }
  return true;
});
