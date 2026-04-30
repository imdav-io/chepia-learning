import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/vocabulary_term.dart';

class VocabularyRepository {
  VocabularyRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure('Sesión no iniciada');
    }
    return id;
  }

  Future<List<VocabularyTerm>> fetchForLesson({
    required String bookId,
    required String lessonId,
  }) async {
    try {
      final res = await _client
          .from('user_vocabulary')
          .select('id, book_id, lesson_id, term, note, created_at, updated_at')
          .eq('user_id', _userId)
          .eq('book_id', bookId)
          .eq('lesson_id', lessonId)
          .order('updated_at', ascending: false);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(VocabularyTerm.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.warn('fetchForLesson vocabulary failed', e, st);
      return const [];
    }
  }

  Future<VocabularyTerm> saveTerm({
    required String bookId,
    required String lessonId,
    required String term,
  }) async {
    final cleanTerm = term.trim();
    if (cleanTerm.isEmpty) {
      throw const ValidationFailure('La palabra no puede estar vacía');
    }

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final res = await _client
          .from('user_vocabulary')
          .upsert({
            'user_id': _userId,
            'book_id': bookId,
            'lesson_id': lessonId,
            'term': cleanTerm,
            'normalized_term': cleanTerm.toLowerCase(),
            'updated_at': now,
          }, onConflict: 'user_id,book_id,lesson_id,normalized_term')
          .select('id, book_id, lesson_id, term, note, created_at, updated_at')
          .single();
      return VocabularyTerm.fromMap(res);
    } catch (e, st) {
      AppLogger.error('saveTerm vocabulary failed', e, st);
      throw ServerFailure('No se pudo guardar la palabra', cause: e);
    }
  }

  Future<void> deleteTerm(String id) async {
    try {
      await _client
          .from('user_vocabulary')
          .delete()
          .eq('id', id)
          .eq('user_id', _userId);
    } catch (e, st) {
      AppLogger.error('deleteTerm vocabulary failed', e, st);
      throw ServerFailure('No se pudo borrar la palabra', cause: e);
    }
  }
}
