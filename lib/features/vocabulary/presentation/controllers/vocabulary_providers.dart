import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../data/repositories/vocabulary_repository.dart';
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
