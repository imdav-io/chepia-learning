import 'package:chepia_learning/core/errors/failure.dart';
import 'package:chepia_learning/features/auth/domain/repositories/auth_repository.dart';
import 'package:chepia_learning/features/auth/presentation/controllers/auth_providers.dart';
import 'package:chepia_learning/features/auth/presentation/controllers/sign_in_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository mockAuthRepository;
  late ProviderContainer container;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(mockAuthRepository)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('SignInController', () {
    test('initial state is correct', () {
      expect(container.read(signInControllerProvider), const SignInState());
    });

    test('Google sign-in success clears submitting state', () async {
      when(
        () => mockAuthRepository.signInWithGoogle(),
      ).thenAnswer((_) async {});

      final controller = container.read(signInControllerProvider.notifier);

      await controller.signInWithGoogle();

      verify(() => mockAuthRepository.signInWithGoogle()).called(1);
      expect(container.read(signInControllerProvider).isSubmitting, isFalse);
      expect(container.read(signInControllerProvider).errorMessage, isNull);
    });

    test('Google sign-in failure updates state with error message', () async {
      when(
        () => mockAuthRepository.signInWithGoogle(),
      ).thenThrow(const AuthFailure('No se pudo iniciar sesión con Google'));

      final controller = container.read(signInControllerProvider.notifier);

      await controller.signInWithGoogle();

      expect(container.read(signInControllerProvider).isSubmitting, isFalse);
      expect(
        container.read(signInControllerProvider).errorMessage,
        'No se pudo iniciar sesión con Google',
      );
    });
  });
}
