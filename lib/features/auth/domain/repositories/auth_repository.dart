import '../entities/app_user.dart';

abstract class AuthRepository {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;

  /// Inicia el flujo OAuth con Google. La sesión se completa de forma
  /// asíncrona vía [authStateChanges]. En web el callback vuelve a la página
  /// actual; en mobile usa el deep link `io.imdav.chepia.learning://login-callback`.
  Future<void> signInWithGoogle();
  Future<void> signOut();
}
