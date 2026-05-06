import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/controllers/auth_providers.dart';
import '../features/auth/presentation/screens/sign_in_screen.dart';
import '../features/catalog/presentation/screens/catalog_screen.dart';
import '../features/catalog/presentation/screens/level_books_screen.dart';
import '../features/lesson/presentation/screens/book_reader_screen.dart';
import '../features/onboarding/presentation/screens/splash_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/progress/presentation/screens/progress_screen.dart';
import '../features/quiz/presentation/screens/quiz_screen.dart';
import '../features/vocabulary/presentation/screens/flashcards_screen.dart';
import 'main_shell.dart';
import 'route_observer.dart';

final _rootNavKey = GlobalKey<NavigatorState>();
final _learnNavKey = GlobalKey<NavigatorState>();
final _progressNavKey = GlobalKey<NavigatorState>();
final _profileNavKey = GlobalKey<NavigatorState>();

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  void notify() => notifyListeners();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final notifier = _RouterRefreshNotifier(authRepo.authStateChanges());
  // Re-evaluamos redirect cuando termina el bootstrap de auth.
  ref.listen(authBootstrapProvider, (_, _) => notifier.notify());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    navigatorKey: _rootNavKey,
    initialLocation: '/splash',
    observers: [appRouteObserver],
    refreshListenable: notifier,
    debugLogDiagnostics: true,
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            state.error?.toString() ?? 'No se pudo abrir esta pantalla.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final bootstrap = ref.read(authBootstrapProvider);

      // Mientras Supabase termina de restaurar la sesión persistida,
      // mantenemos al usuario en /splash en vez de mandarlo a /sign-in.
      if (!bootstrap.hasValue) {
        return loc == '/splash' ? null : '/splash';
      }

      final user = authRepo.currentUser;
      final isSplash = loc == '/splash';
      final isAuth = loc == '/sign-in';

      if (isSplash) {
        return user == null ? '/sign-in' : '/';
      }
      if (user == null && !isAuth) return '/sign-in';
      if (user != null && isAuth) return '/';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),

      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _learnNavKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const CatalogScreen(),
                routes: [
                  GoRoute(
                    path: 'levels/:levelCode',
                    builder: (_, s) => LevelBooksScreen(
                      levelCode: s.pathParameters['levelCode']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _progressNavKey,
            routes: [
              GoRoute(
                path: '/progress',
                builder: (_, _) => const ProgressScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: '/book/:bookSlug',
        parentNavigatorKey: _rootNavKey,
        builder: (_, s) =>
            BookReaderScreen(bookSlug: s.pathParameters['bookSlug']!),
      ),
      GoRoute(
        path: '/quiz/:bookSlug/:lessonNumber',
        parentNavigatorKey: _rootNavKey,
        builder: (_, s) => QuizScreen(
          bookSlug: s.pathParameters['bookSlug']!,
          lessonNumber: int.parse(s.pathParameters['lessonNumber']!),
        ),
      ),
      GoRoute(
        path: '/flashcards/:bookSlug/:lessonNumber',
        parentNavigatorKey: _rootNavKey,
        builder: (_, s) => FlashcardsScreen(
          bookSlug: s.pathParameters['bookSlug']!,
          lessonNumber: int.parse(s.pathParameters['lessonNumber']!),
        ),
      ),
    ],
  );
});
