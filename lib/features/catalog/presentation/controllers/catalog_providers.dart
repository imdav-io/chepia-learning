import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../data/repositories/asset_repository.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/lesson.dart';
import '../../domain/entities/level.dart';
import '../../domain/repositories/catalog_repository.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return SupabaseCatalogRepository(ref.watch(supabaseClientProvider));
});

final assetRepositoryProvider = Provider<AssetRepository>((ref) {
  return AssetRepository(ref.watch(supabaseClientProvider));
});

final levelsProvider = FutureProvider<List<Level>>((ref) {
  return ref.watch(catalogRepositoryProvider).fetchLevels();
});

final booksByLevelProvider = FutureProvider.family<List<Book>, String>((
  ref,
  levelCode,
) {
  return ref.watch(catalogRepositoryProvider).fetchBooksByLevel(levelCode);
});

final lessonsProvider = FutureProvider.family<List<Lesson>, String>((
  ref,
  bookId,
) {
  return ref.watch(catalogRepositoryProvider).fetchLessons(bookId);
});

Future<Asset?> _tryFetchAsset(
  Future<Asset?> Function() fetch,
  String label,
) async {
  try {
    return await fetch();
  } on Object catch (e, st) {
    AppLogger.warn('$label no disponible', e, st);
    return null;
  }
}

Future<String?> _tryResolveUrl(
  AssetRepository repo,
  Asset? asset,
  String label,
) async {
  if (asset == null) return null;
  try {
    return await repo.resolveUrl(asset);
  } on Object catch (e, st) {
    AppLogger.warn('$label no se pudo resolver', e, st);
    return null;
  }
}

class LessonAssets {
  const LessonAssets({
    this.pdf,
    this.studyGuide,
    this.audio,
    this.pdfUrl,
    this.studyGuideUrl,
    this.audioUrl,
  });
  final Asset? pdf;
  final Asset? studyGuide;
  final Asset? audio;
  final String? pdfUrl;
  final String? studyGuideUrl;
  final String? audioUrl;
}

final lessonAssetsProvider =
    FutureProvider.family<LessonAssets, ({String bookId, String lessonId})>((
      ref,
      params,
    ) async {
      final catalog = ref.watch(catalogRepositoryProvider);
      final asset = ref.watch(assetRepositoryProvider);

      final pdf = await catalog.fetchBookPdf(params.bookId);
      final studyGuide = await _tryFetchAsset(
        () => catalog.fetchBookStudyGuide(params.bookId),
        'Study guide',
      );
      final audio = await _tryFetchAsset(
        () => catalog.fetchLessonAudio(params.lessonId),
        'Audio de lección',
      );

      final pdfUrl = pdf == null ? null : await asset.resolveUrl(pdf);
      final studyGuideUrl = await _tryResolveUrl(
        asset,
        studyGuide,
        'Study guide',
      );
      final audioUrl = await _tryResolveUrl(asset, audio, 'Audio de lección');

      return LessonAssets(
        pdf: pdf,
        studyGuide: studyGuide,
        audio: audio,
        pdfUrl: pdfUrl,
        studyGuideUrl: studyGuideUrl,
        audioUrl: audioUrl,
      );
    });

/// Resuelve `(bookId, lessonId)` desde `(bookSlug, lessonNumber)` para que
/// los deep links sigan siendo legibles.
final lessonByBookSlugAndNumberProvider =
    FutureProvider.family<
      ({String bookId, Lesson lesson}),
      ({String bookSlug, int lessonNumber})
    >((ref, params) async {
      final supabase = ref.watch(supabaseClientProvider);
      final book = await supabase
          .from('books')
          .select('id')
          .eq('slug', params.bookSlug)
          .maybeSingle();
      if (book == null) {
        throw StateError('Libro no encontrado: ${params.bookSlug}');
      }
      final bookId = book['id'] as String;
      final lessons = await ref
          .watch(catalogRepositoryProvider)
          .fetchLessons(bookId);
      final lesson = lessons.firstWhere(
        (l) => l.number == params.lessonNumber,
        orElse: () =>
            throw StateError('Lección no encontrada: ${params.lessonNumber}'),
      );
      return (bookId: bookId, lesson: lesson);
    });

class LessonWithAudio {
  const LessonWithAudio({required this.lesson, this.audio, this.audioUrl});
  final Lesson lesson;
  final Asset? audio;
  final String? audioUrl;

  bool get hasAudio => audioUrl != null;
}

class BookReaderData {
  const BookReaderData({
    required this.bookId,
    required this.bookTitle,
    required this.bookSlug,
    required this.pdfUrl,
    required this.pdfKey,
    required this.studyGuideUrl,
    required this.studyGuideKey,
    required this.lessons,
  });

  final String bookId;
  final String bookTitle;
  final String bookSlug;
  final String? pdfUrl;
  final String? pdfKey;
  final String? studyGuideUrl;
  final String? studyGuideKey;
  final List<LessonWithAudio> lessons;
}

/// Provee todo lo necesario para el BookReaderScreen en un solo fetch:
/// libro, PDF (URL resuelta) y todas las lecciones con sus audios resueltos.
final bookReaderDataProvider = FutureProvider.family<BookReaderData, String>((
  ref,
  bookSlug,
) async {
  final supabase = ref.watch(supabaseClientProvider);
  final catalog = ref.watch(catalogRepositoryProvider);
  final assetRepo = ref.watch(assetRepositoryProvider);

  final book = await supabase
      .from('books')
      .select('id, title, slug')
      .eq('slug', bookSlug)
      .maybeSingle();
  if (book == null) {
    throw StateError('Libro no encontrado: $bookSlug');
  }
  final bookId = book['id'] as String;

  final pdf = await catalog.fetchBookPdf(bookId);
  final studyGuide = await _tryFetchAsset(
    () => catalog.fetchBookStudyGuide(bookId),
    'Study guide',
  );
  final pdfUrl = pdf == null ? null : await assetRepo.resolveUrl(pdf);
  final studyGuideUrl = await _tryResolveUrl(
    assetRepo,
    studyGuide,
    'Study guide',
  );

  final lessons = await catalog.fetchLessons(bookId);
  final lessonsWithAudio = <LessonWithAudio>[];
  for (final l in lessons) {
    final a = await _tryFetchAsset(
      () => catalog.fetchLessonAudio(l.id),
      'Audio de lección ${l.number}',
    );
    final url = await _tryResolveUrl(
      assetRepo,
      a,
      'Audio de lección ${l.number}',
    );
    lessonsWithAudio.add(LessonWithAudio(lesson: l, audio: a, audioUrl: url));
  }

  return BookReaderData(
    bookId: bookId,
    bookTitle: book['title'] as String,
    bookSlug: book['slug'] as String,
    pdfUrl: pdfUrl,
    pdfKey: pdf?.storagePath,
    studyGuideUrl: studyGuideUrl,
    studyGuideKey: studyGuide?.storagePath,
    lessons: lessonsWithAudio,
  );
});
