import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../../catalog/presentation/controllers/catalog_providers.dart';
import '../../data/repositories/quiz_repository_impl.dart';
import '../../domain/entities/quiz.dart';
import '../../domain/repositories/quiz_repository.dart';

final quizRepositoryProvider = Provider<QuizRepository>((ref) {
  return SupabaseQuizRepository(ref.watch(supabaseClientProvider));
});

final lessonQuizProvider =
    FutureProvider.family<Quiz?, ({String bookSlug, int lessonNumber})>((
      ref,
      params,
    ) async {
      final lookup = await ref.watch(
        lessonByBookSlugAndNumberProvider((
          bookSlug: params.bookSlug,
          lessonNumber: params.lessonNumber,
        )).future,
      );
      return ref
          .watch(quizRepositoryProvider)
          .fetchLessonQuiz(lookup.lesson.id);
    });
