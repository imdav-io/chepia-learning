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

const _optimizedPageBookSlugs = {
  'as-it-is-book-1',
  'as-it-is-book-2',
  'as-it-is-book-3',
};

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
    required this.isOptimized,
    required this.pdfUrl,
    required this.pdfKey,
    required this.pageManifestUrl,
    required this.pageManifestKey,
    required this.studyGuideUrl,
    required this.studyGuideKey,
    required this.studyGuideManifestUrl,
    required this.studyGuideManifestKey,
    required this.lessons,
  });

  final String bookId;
  final String bookTitle;
  final String bookSlug;
  final bool isOptimized;
  final String? pdfUrl;
  final String? pdfKey;
  final String? pageManifestUrl;
  final String? pageManifestKey;
  final String? studyGuideUrl;
  final String? studyGuideKey;
  final String? studyGuideManifestUrl;
  final String? studyGuideManifestKey;
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
  final resolvedBookSlug = book['slug'] as String;
  final isOptimized = _optimizedPageBookSlugs.contains(resolvedBookSlug);

  // En libros optimizados, el PDF principal solo se necesita en modo offline.
  // Lo cargamos bajo demanda al abrir ese sheet (ver lazyBookPdfProvider).
  Asset? pdf;
  String? pdfUrl;
  if (!isOptimized) {
    pdf = await catalog.fetchBookPdf(bookId);
    pdfUrl = pdf == null ? null : await assetRepo.resolveUrl(pdf);
  }

  final studyGuide = await _tryFetchAsset(
    () => catalog.fetchBookStudyGuide(bookId),
    'Study guide',
  );
  String? pageManifestKey;
  String? pageManifestUrl;
  if (isOptimized) {
    pageManifestKey = 'books/$resolvedBookSlug/pages/v1/manifest.json';
    pageManifestUrl = await _tryResolveUrl(
      assetRepo,
      Asset(
        id: 'page-manifest-$resolvedBookSlug',
        kind: AssetKind.pdf,
        storagePath: pageManifestKey,
        bookId: bookId,
      ),
      'Manifest de páginas',
    );
  }
  String? studyGuideManifestKey;
  String? studyGuideManifestUrl;
  if (studyGuide != null && isOptimized) {
    studyGuideManifestKey =
        'books/$resolvedBookSlug/study-guide/v1/manifest.json';
    studyGuideManifestUrl = await _tryResolveUrl(
      assetRepo,
      Asset(
        id: 'study-guide-manifest-$resolvedBookSlug',
        kind: AssetKind.pdf,
        storagePath: studyGuideManifestKey,
        bookId: bookId,
      ),
      'Manifest de study guide',
    );
  }
  final studyGuideUrl = await _tryResolveUrl(
    assetRepo,
    studyGuide,
    'Study guide',
  );

  final lessons = [...await catalog.fetchLessons(bookId)]
    ..sort((a, b) => a.number.compareTo(b.number));
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
    bookSlug: resolvedBookSlug,
    isOptimized: isOptimized,
    pdfUrl: pdfUrl,
    pdfKey: pdf?.storagePath,
    pageManifestUrl: pageManifestUrl,
    pageManifestKey: pageManifestKey,
    studyGuideUrl: studyGuideUrl,
    studyGuideKey: studyGuide?.storagePath,
    studyGuideManifestUrl: studyGuideManifestUrl,
    studyGuideManifestKey: studyGuideManifestKey,
    lessons: lessonsWithAudio,
  );
});

/// Carga bajo demanda el PDF principal de un libro optimizado.
/// Lo usa el sheet de modo offline para no penalizar la apertura del lector.
final lazyBookPdfProvider =
    FutureProvider.family<({String? key, String? url})?, String>((
      ref,
      bookId,
    ) async {
      final catalog = ref.watch(catalogRepositoryProvider);
      final assetRepo = ref.watch(assetRepositoryProvider);
      final pdf = await _tryFetchAsset(
        () => catalog.fetchBookPdf(bookId),
        'PDF principal (offline)',
      );
      if (pdf == null) return null;
      final url = await _tryResolveUrl(
        assetRepo,
        pdf,
        'PDF principal (offline)',
      );
      if (url == null) return null;
      return (key: pdf.storagePath, url: url);
    });
