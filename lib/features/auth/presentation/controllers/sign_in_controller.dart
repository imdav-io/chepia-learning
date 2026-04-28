import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import 'auth_providers.dart';

class SignInState {
  const SignInState({this.isSubmitting = false, this.errorMessage});
  final bool isSubmitting;
  final String? errorMessage;

  SignInState copyWith({bool? isSubmitting, String? errorMessage, bool clearError = false}) {
    return SignInState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class SignInController extends StateNotifier<SignInState> {
  SignInController(this._ref) : super(const SignInState());
  final Ref _ref;

  Future<bool> signIn({required String email, required String password}) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _ref.read(authRepositoryProvider).signInWithEmail(email: email, password: password);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on Failure catch (e) {
      AppLogger.warn('Sign in failure: ${e.message}');
      state = state.copyWith(isSubmitting: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: 'Error inesperado');
      return false;
    }
  }

  Future<bool> signUp({required String email, required String password}) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _ref.read(authRepositoryProvider).signUpWithEmail(email: email, password: password);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on Failure catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: 'Error inesperado');
      return false;
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _ref.read(authRepositoryProvider).signInWithGoogle();
      // El estado de autenticación se completa vía authStateChanges.
      state = state.copyWith(isSubmitting: false);
    } on Failure catch (e) {
      AppLogger.warn('Google sign-in failed: ${e.message}');
      state = state.copyWith(isSubmitting: false, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: 'Error inesperado');
    }
  }

  Future<void> signInWithApple() async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _ref.read(authRepositoryProvider).signInWithApple();
      state = state.copyWith(isSubmitting: false);
    } on Failure catch (e) {
      AppLogger.warn('Apple sign-in failed: ${e.message}');
      state = state.copyWith(isSubmitting: false, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: 'Error inesperado');
    }
  }
}

final signInControllerProvider =
    StateNotifierProvider<SignInController, SignInState>((ref) {
  return SignInController(ref);
});
