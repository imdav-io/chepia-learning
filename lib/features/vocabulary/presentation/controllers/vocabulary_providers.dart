import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../data/repositories/vocabulary_repository.dart';
import '../../domain/entities/lesson_vocabulary_term.dart';
import '../../domain/entities/vocabulary_term.dart';

typedef LessonVocabularyParams = ({String bookId, String lessonId});

final vocabularyRepositoryProvider = Provider<VocabularyRepository>((ref) {
  return VocabularyRepository(ref.watch(supabaseClientProvider));
});

final lessonVocabularyProvider =
    FutureProvider.family<List<VocabularyTerm>, LessonVocabularyParams>((
      ref,
      params,
    ) {
      return ref
          .watch(vocabularyRepositoryProvider)
          .fetchForLesson(bookId: params.bookId, lessonId: params.lessonId);
    });

/// Vocabulario curado de una lección (catálogo, alimentado por
/// `generate-vocabulary.mjs`). Lo usa la pantalla de flashcards como fuente
/// por defecto. Si está vacío, la UI cae al vocabulario personal del usuario.
final curatedLessonVocabularyProvider =
    FutureProvider.family<List<LessonVocabularyTerm>, String>((ref, lessonId) {
      return ref
          .watch(vocabularyRepositoryProvider)
          .fetchCuratedForLesson(lessonId);
    });
