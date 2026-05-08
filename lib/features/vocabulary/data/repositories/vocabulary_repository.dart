import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/lesson_vocabulary_term.dart';
import '../../domain/entities/vocabulary_term.dart';

class VocabularyRepository {
  VocabularyRepository(this._client);

  final SupabaseClient _client;
  static const _termSelect =
      'id, book_id, lesson_id, term, note, review_state, review_count, '
      'interval_days, due_at, last_reviewed_at, created_at, updated_at';
  static const _legacyTermSelect =
      'id, book_id, lesson_id, term, note, created_at, updated_at';

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
      final res = await _selectUserVocabulary(_termSelect)
          .eq('user_id', _userId)
          .eq('book_id', bookId)
          .eq('lesson_id', lessonId)
          .order('due_at', ascending: true, nullsFirst: true)
          .order('updated_at', ascending: false);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(VocabularyTerm.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.warn('fetchForLesson vocabulary with review failed', e, st);
      return _fetchForLessonLegacy(bookId: bookId, lessonId: lessonId);
    }
  }

  Future<List<VocabularyTerm>> _fetchForLessonLegacy({
    required String bookId,
    required String lessonId,
  }) async {
    try {
      final res = await _selectUserVocabulary(_legacyTermSelect)
          .eq('user_id', _userId)
          .eq('book_id', bookId)
          .eq('lesson_id', lessonId)
          .order('updated_at', ascending: false);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(VocabularyTerm.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.warn('fetchForLesson vocabulary legacy failed', e, st);
      return const [];
    }
  }

  Future<List<LessonVocabularyTerm>> fetchCuratedForLesson(
    String lessonId,
  ) async {
    try {
      final res = await _client
          .from('lesson_vocabulary')
          .select(
            'id, lesson_id, term, meaning_es, example_en, pronunciation, image_url, image_alt, audio_storage_path, sort_order',
          )
          .eq('lesson_id', lessonId)
          .order('sort_order');
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(LessonVocabularyTerm.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.warn('fetchCuratedForLesson failed', e, st);
      return _fetchCuratedForLessonLegacy(lessonId);
    }
  }

  Future<List<LessonVocabularyTerm>> _fetchCuratedForLessonLegacy(
    String lessonId,
  ) async {
    try {
      final res = await _client
          .from('lesson_vocabulary')
          .select(
            'id, lesson_id, term, meaning_es, example_en, pronunciation, sort_order',
          )
          .eq('lesson_id', lessonId)
          .order('sort_order');
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(LessonVocabularyTerm.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.warn('fetchCuratedForLesson legacy failed', e, st);
      return const [];
    }
  }

  Future<VocabularyTerm> saveTerm({
    required String bookId,
    required String lessonId,
    required String term,
    String? note,
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
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            'review_state': VocabularyReviewState.newTerm.dbValue,
            'review_count': 0,
            'interval_days': 0,
            'due_at': now,
            'updated_at': now,
          }, onConflict: 'user_id,book_id,lesson_id,normalized_term')
          .select(_termSelect)
          .single();
      return VocabularyTerm.fromMap(res);
    } catch (e, st) {
      AppLogger.warn('saveTerm vocabulary with review failed', e, st);
      return _saveTermLegacy(bookId: bookId, lessonId: lessonId, term: term);
    }
  }

  Future<VocabularyTerm> _saveTermLegacy({
    required String bookId,
    required String lessonId,
    required String term,
  }) async {
    final cleanTerm = term.trim();
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
          .select(_legacyTermSelect)
          .single();
      return VocabularyTerm.fromMap(res);
    } catch (e, st) {
      AppLogger.error('saveTerm vocabulary legacy failed', e, st);
      throw ServerFailure('No se pudo guardar la palabra', cause: e);
    }
  }

  Future<VocabularyTerm?> reviewTerm({
    required String bookId,
    required String lessonId,
    required String term,
    String? note,
    required bool known,
  }) async {
    final cleanTerm = term.trim();
    if (cleanTerm.isEmpty) return null;

    try {
      final current = await _fetchExistingReviewTerm(
        bookId: bookId,
        lessonId: lessonId,
        normalizedTerm: cleanTerm.toLowerCase(),
      );
      final next = _nextReviewPayload(
        current: current,
        known: known,
        now: DateTime.now().toUtc(),
      );
      final res = await _client
          .from('user_vocabulary')
          .upsert({
            'user_id': _userId,
            'book_id': bookId,
            'lesson_id': lessonId,
            'term': cleanTerm,
            'normalized_term': cleanTerm.toLowerCase(),
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            ...next,
          }, onConflict: 'user_id,book_id,lesson_id,normalized_term')
          .select(_termSelect)
          .single();
      return VocabularyTerm.fromMap(res);
    } catch (e, st) {
      AppLogger.warn('reviewTerm failed', e, st);
      try {
        return saveTerm(
          bookId: bookId,
          lessonId: lessonId,
          term: cleanTerm,
          note: note,
        );
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<VocabularyTerm>> fetchDueReviewTerms({int limit = 20}) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final res = await _selectUserVocabulary(_termSelect)
          .eq('user_id', _userId)
          .lte('due_at', now)
          .order('due_at', ascending: true)
          .limit(limit);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(VocabularyTerm.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.warn('fetchDueReviewTerms failed', e, st);
      return const [];
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

  Future<String> resolveCuratedSpeechUrl({
    required String lessonVocabularyId,
    required String usage,
    String? storagePath,
  }) async {
    const ttlSeconds = 60 * 60 * 24;
    final cleanPath = storagePath?.trim();
    if (usage == 'term' && cleanPath != null && cleanPath.isNotEmpty) {
      try {
        return await _client.storage
            .from('vocab-audio')
            .createSignedUrl(cleanPath, ttlSeconds);
      } catch (e, st) {
        AppLogger.warn('create vocab audio signed url failed', e, st);
      }
    }

    try {
      final res = await _client.functions.invoke(
        'vocabulary-tts',
        body: {
          'lessonVocabularyId': lessonVocabularyId,
          'usage': usage == 'example' ? 'example' : 'term',
        },
      );
      if (res.status >= 400) {
        throw ServerFailure(
          'vocabulary-tts respondió ${res.status}: ${res.data}',
        );
      }
      final data = res.data;
      if (data is Map && data['signedUrl'] is String) {
        return data['signedUrl'] as String;
      }
      throw const ServerFailure('Respuesta inválida de vocabulary-tts.');
    } on FunctionException catch (e) {
      throw ServerFailure(
        'No pudimos generar el audio (${e.status}). ${e.details ?? ''}',
        cause: e,
      );
    } catch (e) {
      if (e is Failure) rethrow;
      throw UnknownFailure('Error inesperado en vocabulary-tts', e);
    }
  }

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _selectUserVocabulary(
    String columns,
  ) {
    return _client.from('user_vocabulary').select(columns);
  }

  Future<VocabularyTerm?> _fetchExistingReviewTerm({
    required String bookId,
    required String lessonId,
    required String normalizedTerm,
  }) async {
    final row = await _selectUserVocabulary(_termSelect)
        .eq('user_id', _userId)
        .eq('book_id', bookId)
        .eq('lesson_id', lessonId)
        .eq('normalized_term', normalizedTerm)
        .maybeSingle();
    return row == null ? null : VocabularyTerm.fromMap(row);
  }

  Map<String, dynamic> _nextReviewPayload({
    required VocabularyTerm? current,
    required bool known,
    required DateTime now,
  }) {
    final reviewCount = (current?.reviewCount ?? 0) + 1;
    final currentInterval = current?.intervalDays ?? 0;
    final currentState = current?.reviewState ?? VocabularyReviewState.newTerm;

    late final VocabularyReviewState nextState;
    late final int nextInterval;

    if (!known) {
      nextState = VocabularyReviewState.learning;
      nextInterval = 1;
    } else {
      switch (currentState) {
        case VocabularyReviewState.newTerm:
          nextState = VocabularyReviewState.learning;
          nextInterval = 1;
        case VocabularyReviewState.learning:
          nextState = reviewCount >= 3
              ? VocabularyReviewState.mastered
              : VocabularyReviewState.learning;
          nextInterval = currentInterval <= 1 ? 3 : currentInterval + 2;
        case VocabularyReviewState.mastered:
          nextState = VocabularyReviewState.mastered;
          nextInterval = (currentInterval <= 0 ? 7 : currentInterval * 2)
              .clamp(7, 90)
              .toInt();
      }
    }

    return {
      'review_state': nextState.dbValue,
      'review_count': reviewCount,
      'interval_days': nextInterval,
      'last_reviewed_at': now.toIso8601String(),
      'due_at': now.add(Duration(days: nextInterval)).toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
  }
}
