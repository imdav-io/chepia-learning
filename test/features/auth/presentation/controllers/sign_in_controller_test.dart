import 'package:chepia_learning/features/auth/domain/entities/app_user.dart';
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
      overrides: [
        authRepositoryProvider.overrideWithValue(mockAuthRepository),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('SignInController', () {
    test('initial state is correct', () {
      expect(container.read(signInControllerProvider), const SignInState());
    });

    test('signIn success updates state and returns true', () async {
      const user = AppUser(id: '123', email: 'test@example.com');
      when(() => mockAuthRepository.signInWithEmail(
            email: 'test@example.com',
            password: 'password123',
          )).thenAnswer((_) async => user);

      final controller = container.read(signInControllerProvider.notifier);
      
      final result = await controller.signIn(
        email: 'test@example.com',
        password: 'password123',
      );

      expect(result, isTrue);
      expect(container.read(signInControllerProvider).isSubmitting, isFalse);
      expect(container.read(signInControllerProvider).errorMessage, isNull);
    });

    test('signIn failure updates state with error message', () async {
      when(() => mockAuthRepository.signInWithEmail(
            email: 'test@example.com',
            password: 'wrong-password',
          )).thenThrow(Exception('Invalid credentials'));

      final controller = container.read(signInControllerProvider.notifier);
      
      final result = await controller.signIn(
        email: 'test@example.com',
        password: 'wrong-password',
      );

      expect(result, isFalse);
      expect(container.read(signInControllerProvider).isSubmitting, isFalse);
      expect(container.read(signInControllerProvider).errorMessage, isNotNull);
    });
  });
}
