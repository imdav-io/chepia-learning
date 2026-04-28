import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/lesson_progress.dart';
import '../../domain/repositories/progress_repository.dart';

class SupabaseProgressRepository implements ProgressRepository {
  SupabaseProgressRepository(this._client);
  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure('Sesión no iniciada');
    }
    return id;
  }

  @override
  Future<ReadingProgress?> fetchReading(String lessonId) async {
    try {
      final res = await _client
          .from('reading_progress')
          .select('lesson_id, last_page, is_completed, updated_at')
          .eq('user_id', _userId)
          .eq('lesson_id', lessonId)
          .maybeSingle();
      if (res == null) return null;
      return ReadingProgress.fromMap(res);
    } catch (e, st) {
      AppLogger.warn('fetchReading failed', e, st);
      return null;
    }
  }

  @override
  Future<AudioProgress?> fetchAudio(String lessonId) async {
    try {
      final res = await _client
          .from('audio_progress')
          .select('lesson_id, last_position_sec, is_completed, updated_at')
          .eq('user_id', _userId)
          .eq('lesson_id', lessonId)
          .maybeSingle();
      if (res == null) return null;
      return AudioProgress.fromMap(res);
    } catch (e, st) {
      AppLogger.warn('fetchAudio failed', e, st);
      return null;
    }
  }

  @override
  Future<List<ReadingProgress>> fetchReadingForBook(String bookId) async {
    try {
      final lessonIds = await _lessonIdsForBook(bookId);
      if (lessonIds.isEmpty) return const [];
      final res = await _client
          .from('reading_progress')
          .select('lesson_id, last_page, is_completed, updated_at')
          .eq('user_id', _userId)
          .inFilter('lesson_id', lessonIds);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(ReadingProgress.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.warn('fetchReadingForBook failed', e, st);
      return const [];
    }
  }

  @override
  Future<List<AudioProgress>> fetchAudioForBook(String bookId) async {
    try {
      final lessonIds = await _lessonIdsForBook(bookId);
      if (lessonIds.isEmpty) return const [];
      final res = await _client
          .from('audio_progress')
          .select('lesson_id, last_position_sec, is_completed, updated_at')
          .eq('user_id', _userId)
          .inFilter('lesson_id', lessonIds);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(AudioProgress.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.warn('fetchAudioForBook failed', e, st);
      return const [];
    }
  }

  Future<List<String>> _lessonIdsForBook(String bookId) async {
    final res = await _client.from('lessons').select('id').eq('book_id', bookId);
    return (res as List).map((m) => (m as Map)['id'] as String).toList();
  }

  @override
  Future<void> saveReading({
    required String lessonId,
    required int lastPage,
    bool? isCompleted,
  }) async {
    try {
      final payload = <String, dynamic>{
        'user_id': _userId,
        'lesson_id': lessonId,
        'last_page': lastPage,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (isCompleted != null) payload['is_completed'] = isCompleted;
      await _client.from('reading_progress').upsert(payload);
    } catch (e, st) {
      AppLogger.warn('saveReading failed', e, st);
    }
  }

  @override
  Future<void> saveAudio({
    required String lessonId,
    required int lastPositionSec,
    bool? isCompleted,
  }) async {
    try {
      final payload = <String, dynamic>{
        'user_id': _userId,
        'lesson_id': lessonId,
        'last_position_sec': lastPositionSec,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (isCompleted != null) payload['is_completed'] = isCompleted;
      await _client.from('audio_progress').upsert(payload);
    } catch (e, st) {
      AppLogger.warn('saveAudio failed', e, st);
    }
  }
}
