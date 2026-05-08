import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/lesson.dart';
import '../../domain/entities/level.dart';
import '../../domain/repositories/catalog_repository.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Level>> fetchLevels() async {
    try {
      final res = await _client
          .from('levels')
          .select('id, code, name, sort_order')
          .order('sort_order');
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(Level.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.error('fetchLevels failed', e, st);
      throw ServerFailure('No se pudieron cargar los niveles', cause: e);
    }
  }

  @override
  Future<List<Book>> fetchBooksByLevel(String levelCode) async {
    try {
      final levelRes = await _client
          .from('levels')
          .select('id')
          .eq('code', levelCode)
          .maybeSingle();
      if (levelRes == null) return const [];

      final res = await _client
          .from('books')
          .select('id, level_id, title, slug, description, cover_url, language')
          .eq('level_id', levelRes['id'] as String)
          .order('sort_order');
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(Book.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.error('fetchBooksByLevel failed', e, st);
      throw ServerFailure('No se pudieron cargar los libros', cause: e);
    }
  }

  @override
  Future<List<Lesson>> fetchLessons(String bookId) async {
    try {
      final res = await _client
          .from('lessons')
          .select('id, book_id, number, title, pdf_start_page, pdf_end_page')
          .eq('book_id', bookId)
          .order('number');
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(Lesson.fromMap)
          .toList();
    } catch (e, st) {
      AppLogger.error('fetchLessons failed', e, st);
      throw ServerFailure('No se pudieron cargar las lecciones', cause: e);
    }
  }

  @override
  Future<Asset?> fetchBookPdf(String bookId) async {
    try {
      final res = await _client
          .from('assets')
          .select(
            'id, kind, storage_path, lesson_id, book_id, mime_type, size_bytes, duration_sec, pages, version',
          )
          .eq('book_id', bookId)
          .eq('kind', 'pdf')
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      return Asset.fromMap(res);
    } catch (e, st) {
      AppLogger.error('fetchBookPdf failed', e, st);
      throw ServerFailure('No se pudo obtener el PDF', cause: e);
    }
  }

  @override
  Future<Asset?> fetchBookStudyGuide(String bookId) async {
    try {
      final res = await _client
          .from('assets')
          .select(
            'id, kind, storage_path, lesson_id, book_id, mime_type, size_bytes, duration_sec, pages, version',
          )
          .eq('book_id', bookId)
          .eq('kind', 'study_guide')
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      return Asset.fromMap(res);
    } catch (e, st) {
      AppLogger.error('fetchBookStudyGuide failed', e, st);
      throw ServerFailure('No se pudo obtener la guía de estudio', cause: e);
    }
  }

  @override
  Future<Asset?> fetchLessonAudio(String lessonId) async {
    try {
      final res = await _client
          .from('assets')
          .select(
            'id, kind, storage_path, lesson_id, book_id, mime_type, size_bytes, duration_sec, pages, version',
          )
          .eq('lesson_id', lessonId)
          .eq('kind', 'audio')
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      return Asset.fromMap(res);
    } catch (e, st) {
      AppLogger.error('fetchLessonAudio failed', e, st);
      throw ServerFailure('No se pudo obtener el audio', cause: e);
    }
  }

  @override
  Future<Map<String, Asset>> fetchLessonAudios(List<String> lessonIds) async {
    if (lessonIds.isEmpty) return const {};
    try {
      final res = await _client
          .from('assets')
          .select(
            'id, kind, storage_path, lesson_id, book_id, mime_type, size_bytes, duration_sec, pages, version',
          )
          .eq('kind', 'audio')
          .inFilter('lesson_id', lessonIds)
          .order('version', ascending: false);
      final latestByLesson = <String, Asset>{};
      for (final row in (res as List).cast<Map<String, dynamic>>()) {
        final asset = Asset.fromMap(row);
        final lessonId = asset.lessonId;
        if (lessonId == null) continue;
        latestByLesson.putIfAbsent(lessonId, () => asset);
      }
      return latestByLesson;
    } catch (e, st) {
      AppLogger.error('fetchLessonAudios failed', e, st);
      throw ServerFailure('No se pudieron obtener los audios', cause: e);
    }
  }
}
