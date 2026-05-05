import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../data/repositories/progress_repository_impl.dart';
import '../../domain/entities/lesson_progress.dart';
import '../../domain/repositories/progress_repository.dart';

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return SupabaseProgressRepository(ref.watch(supabaseClientProvider));
});

class BookProgressSummary {
  const BookProgressSummary({
    required this.byLessonReading,
    required this.byLessonAudio,
  });
  final Map<String, ReadingProgress> byLessonReading;
  final Map<String, AudioProgress> byLessonAudio;

  bool isLessonRead(String lessonId) =>
      byLessonReading[lessonId]?.isCompleted ?? false;
  bool isLessonHeard(String lessonId) =>
      byLessonAudio[lessonId]?.isCompleted ?? false;

  int get readCount =>
      byLessonReading.values.where((r) => r.isCompleted).length;
  int get heardCount => byLessonAudio.values.where((a) => a.isCompleted).length;
}

final bookProgressProvider = FutureProvider.family<BookProgressSummary, String>(
  (ref, bookId) async {
    final repo = ref.watch(progressRepositoryProvider);
    final reads = await repo.fetchReadingForBook(bookId);
    final audios = await repo.fetchAudioForBook(bookId);
    return BookProgressSummary(
      byLessonReading: {for (final r in reads) r.lessonId: r},
      byLessonAudio: {for (final a in audios) a.lessonId: a},
    );
  },
);

class BookProgressOverview {
  const BookProgressOverview({
    required this.bookId,
    required this.bookSlug,
    required this.bookTitle,
    required this.levelName,
    required this.totalLessons,
    required this.totalAudioLessons,
    required this.readCompleted,
    required this.audioCompleted,
    required this.quizTotal,
    required this.quizPassed,
    required this.quizAttempts,
    required this.quizScore,
    required this.quizAnswered,
    required this.pagesRead,
    required this.pagesToday,
    required this.minutesListened,
    required this.minutesThisWeek,
    required this.lastLessonNumber,
    required this.lastLessonTitle,
    required this.lastActivityAt,
    required this.nextLessonNumber,
    required this.nextLessonTitle,
    required this.nextStepLabel,
    required this.studyDayKeys,
  });

  final String bookId;
  final String bookSlug;
  final String bookTitle;
  final String levelName;
  final int totalLessons;
  final int totalAudioLessons;
  final int readCompleted;
  final int audioCompleted;
  final int quizTotal;
  final int quizPassed;
  final int quizAttempts;
  final int quizScore;
  final int quizAnswered;
  final int pagesRead;
  final int pagesToday;
  final int minutesListened;
  final int minutesThisWeek;
  final int? lastLessonNumber;
  final String? lastLessonTitle;
  final DateTime? lastActivityAt;
  final int? nextLessonNumber;
  final String? nextLessonTitle;
  final String? nextStepLabel;
  final List<String> studyDayKeys;

  int get completedUnits => readCompleted + audioCompleted + quizPassed;

  int get totalUnits => totalLessons + totalAudioLessons + quizTotal;

  double get completionRatio =>
      totalUnits == 0 ? 0 : completedUnits / totalUnits;

  int get completionPercent =>
      (completionRatio * 100).round().clamp(0, 100).toInt();

  int get quizAccuracyPercent => quizAnswered == 0
      ? 0
      : ((quizScore / quizAnswered) * 100).round().clamp(0, 100).toInt();

  int get listeningPercent => totalAudioLessons == 0
      ? 0
      : ((audioCompleted / totalAudioLessons) * 100)
            .round()
            .clamp(0, 100)
            .toInt();
}

final progressOverviewProvider = FutureProvider<List<BookProgressOverview>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return const [];

  // Cada query se hace por separado y con fallback a lista vacía. Si una
  // tabla auxiliar no existe o falla, la pantalla sigue mostrando el resto
  // del progreso en vez de quedarse atorada.
  Future<List<dynamic>> safeFetch(
    String label,
    Future<dynamic> Function() run,
  ) async {
    try {
      final res = await run();
      return res is List ? res : const <dynamic>[];
    } catch (e, st) {
      AppLogger.warn('progressOverview $label fallo', e, st);
      return const <dynamic>[];
    }
  }

  final results = await Future.wait([
    safeFetch(
      'levels',
      () => client.from('levels').select('id, name').order('sort_order'),
    ),
    safeFetch(
      'books',
      () => client
          .from('books')
          .select('id, level_id, title, slug')
          .order('sort_order'),
    ),
    safeFetch(
      'lessons',
      () => client
          .from('lessons')
          .select('id, book_id, number, title, pdf_start_page, pdf_end_page')
          .order('number'),
    ),
    safeFetch(
      'reading_progress',
      () => client
          .from('reading_progress')
          .select('lesson_id, last_page, is_completed, updated_at')
          .eq('user_id', userId),
    ),
    safeFetch(
      'audio_progress',
      () => client
          .from('audio_progress')
          .select('lesson_id, last_position_sec, is_completed, updated_at')
          .eq('user_id', userId),
    ),
    safeFetch(
      'audio_assets',
      () => client
          .from('assets')
          .select('lesson_id, duration_sec')
          .eq('kind', 'audio'),
    ),
    safeFetch(
      'quizzes',
      () =>
          client.from('quizzes').select('id, lesson_id').eq('kind', 'lesson'),
    ),
    safeFetch(
      'quiz_attempts',
      () => client
          .from('quiz_attempts')
          .select('quiz_id, passed, score, total, started_at, finished_at')
          .eq('user_id', userId),
    ),
  ]);

  final levels = results[0].cast<Map<String, dynamic>>();
  final books = results[1].cast<Map<String, dynamic>>();
  final lessons = results[2].cast<Map<String, dynamic>>();
  final readings = results[3]
      .cast<Map<String, dynamic>>()
      .map(ReadingProgress.fromMap)
      .toList();
  final audios = results[4]
      .cast<Map<String, dynamic>>()
      .map(AudioProgress.fromMap)
      .toList();
  final audioAssets = results[5].cast<Map<String, dynamic>>();
  final quizzes = results[6].cast<Map<String, dynamic>>();
  final attempts = results[7].cast<Map<String, dynamic>>();

  final levelNameById = <String, String>{
    for (final row in levels) row['id'] as String: row['name'] as String,
  };
  final lessonsByBook = <String, List<Map<String, dynamic>>>{};
  final lessonBookById = <String, String>{};
  final lessonById = <String, Map<String, dynamic>>{};
  for (final lesson in lessons) {
    final bookId = lesson['book_id'] as String;
    final lessonId = lesson['id'] as String;
    lessonsByBook.putIfAbsent(bookId, () => []).add(lesson);
    lessonBookById[lessonId] = bookId;
    lessonById[lessonId] = lesson;
  }

  final readingByLesson = {for (final r in readings) r.lessonId: r};
  final audioByLesson = {for (final a in audios) a.lessonId: a};
  final audioDurationByLesson = <String, int>{};
  final audioLessonIds = <String>{};
  for (final asset in audioAssets) {
    final lessonId = asset['lesson_id'] as String?;
    final duration = (asset['duration_sec'] as num?)?.toInt();
    if (lessonId != null) {
      audioLessonIds.add(lessonId);
      if (duration != null && duration > 0) {
        audioDurationByLesson[lessonId] = duration;
      }
    }
  }

  final quizLessonById = <String, String>{};
  final quizIdByLesson = <String, String>{};
  final quizIdsByBook = <String, Set<String>>{};
  for (final quiz in quizzes) {
    final quizId = quiz['id'] as String;
    final lessonId = quiz['lesson_id'] as String;
    final bookId = lessonBookById[lessonId];
    quizLessonById[quizId] = lessonId;
    quizIdByLesson[lessonId] = quizId;
    if (bookId != null) {
      quizIdsByBook.putIfAbsent(bookId, () => <String>{}).add(quizId);
    }
  }

  final passedQuizIds = <String>{};
  final latestActivityByLesson = <String, DateTime>{};

  void rememberActivity(String? lessonId, DateTime? date) {
    if (lessonId == null || date == null) return;
    final previous = latestActivityByLesson[lessonId];
    if (previous == null || date.isAfter(previous)) {
      latestActivityByLesson[lessonId] = date;
    }
  }

  for (final reading in readings) {
    rememberActivity(reading.lessonId, reading.updatedAt);
  }
  for (final audio in audios) {
    rememberActivity(audio.lessonId, audio.updatedAt);
  }
  for (final attempt in attempts) {
    final quizId = attempt['quiz_id'] as String?;
    if (quizId == null) continue;
    if ((attempt['passed'] as bool?) ?? false) {
      passedQuizIds.add(quizId);
    }
    rememberActivity(
      quizLessonById[quizId],
      _parseDate(attempt['finished_at']) ?? _parseDate(attempt['started_at']),
    );
  }

  return [
    for (final book in books)
      _buildOverview(
        book: book,
        levelName: levelNameById[book['level_id'] as String?] ?? '',
        lessons: lessonsByBook[book['id'] as String] ?? const [],
        readingByLesson: readingByLesson,
        audioByLesson: audioByLesson,
        audioDurationByLesson: audioDurationByLesson,
        audioLessonIds: audioLessonIds,
        quizIdByLesson: quizIdByLesson,
        quizIds: quizIdsByBook[book['id'] as String] ?? const <String>{},
        passedQuizIds: passedQuizIds,
        attempts: attempts,
        latestActivityByLesson: latestActivityByLesson,
        lessonById: lessonById,
      ),
  ];
});

BookProgressOverview _buildOverview({
  required Map<String, dynamic> book,
  required String levelName,
  required List<Map<String, dynamic>> lessons,
  required Map<String, ReadingProgress> readingByLesson,
  required Map<String, AudioProgress> audioByLesson,
  required Map<String, int> audioDurationByLesson,
  required Set<String> audioLessonIds,
  required Map<String, String> quizIdByLesson,
  required Set<String> quizIds,
  required Set<String> passedQuizIds,
  required List<Map<String, dynamic>> attempts,
  required Map<String, DateTime> latestActivityByLesson,
  required Map<String, Map<String, dynamic>> lessonById,
}) {
  var readCompleted = 0;
  var audioCompleted = 0;
  var pagesRead = 0;
  var pagesToday = 0;
  var secondsListened = 0;
  var secondsThisWeek = 0;
  var totalAudioLessons = 0;
  String? lastLessonId;
  DateTime? lastActivityAt;
  int? nextLessonNumber;
  String? nextLessonTitle;
  String? nextStepLabel;
  final studyDayKeys = <String>{};
  final now = DateTime.now();
  final weekStart = _startOfWeek(now);

  for (final lesson in lessons) {
    final lessonId = lesson['id'] as String;
    final reading = readingByLesson[lessonId];
    if (reading != null) {
      if (reading.isCompleted) readCompleted++;
      final pagesForLesson = _pagesReadForLesson(lesson, reading.lastPage);
      pagesRead += pagesForLesson;
      if (_isSameLocalDay(reading.updatedAt, now)) {
        pagesToday += pagesForLesson;
      }
      _rememberStudyDay(studyDayKeys, reading.updatedAt);
    }

    final audio = audioByLesson[lessonId];
    if (audioLessonIds.contains(lessonId)) {
      totalAudioLessons++;
    }
    if (audio != null) {
      if (audio.isCompleted) audioCompleted++;
      final duration = audioDurationByLesson[lessonId];
      final listened = duration == null
          ? audio.lastPositionSec
          : audio.lastPositionSec.clamp(0, duration).toInt();
      secondsListened += listened;
      if (_isOnOrAfterLocalDay(audio.updatedAt, weekStart)) {
        secondsThisWeek += listened;
      }
      _rememberStudyDay(studyDayKeys, audio.updatedAt);
    }

    if (nextLessonNumber == null) {
      final quizId = quizIdByLesson[lessonId];
      if (!(reading?.isCompleted ?? false)) {
        nextLessonNumber = (lesson['number'] as num?)?.toInt();
        nextLessonTitle = lesson['title'] as String?;
        nextStepLabel = 'Continuar lectura';
      } else if (audioLessonIds.contains(lessonId) &&
          !(audio?.isCompleted ?? false)) {
        nextLessonNumber = (lesson['number'] as num?)?.toInt();
        nextLessonTitle = lesson['title'] as String?;
        nextStepLabel = 'Escuchar audio';
      } else if (quizId != null && !passedQuizIds.contains(quizId)) {
        nextLessonNumber = (lesson['number'] as num?)?.toInt();
        nextLessonTitle = lesson['title'] as String?;
        nextStepLabel = 'Resolver quiz';
      }
    }

    final activity = latestActivityByLesson[lessonId];
    if (activity != null &&
        (lastActivityAt == null || activity.isAfter(lastActivityAt))) {
      lastActivityAt = activity;
      lastLessonId = lessonId;
    }
  }

  final lastLesson = lastLessonId == null ? null : lessonById[lastLessonId];
  final quizPassed = quizIds.where(passedQuizIds.contains).length;
  var quizAttempts = 0;
  var quizScore = 0;
  var quizAnswered = 0;
  for (final attempt in attempts) {
    final quizId = attempt['quiz_id'] as String?;
    if (quizId == null || !quizIds.contains(quizId)) continue;
    quizAttempts++;
    quizScore += (attempt['score'] as num?)?.toInt() ?? 0;
    quizAnswered += (attempt['total'] as num?)?.toInt() ?? 0;
    _rememberStudyDay(
      studyDayKeys,
      _parseDate(attempt['finished_at']) ?? _parseDate(attempt['started_at']),
    );
  }

  return BookProgressOverview(
    bookId: book['id'] as String,
    bookSlug: book['slug'] as String,
    bookTitle: book['title'] as String,
    levelName: levelName,
    totalLessons: lessons.length,
    totalAudioLessons: totalAudioLessons,
    readCompleted: readCompleted,
    audioCompleted: audioCompleted,
    quizTotal: quizIds.length,
    quizPassed: quizPassed,
    quizAttempts: quizAttempts,
    quizScore: quizScore,
    quizAnswered: quizAnswered,
    pagesRead: pagesRead,
    pagesToday: pagesToday,
    minutesListened: (secondsListened / 60).round(),
    minutesThisWeek: (secondsThisWeek / 60).round(),
    lastLessonNumber: (lastLesson?['number'] as num?)?.toInt(),
    lastLessonTitle: lastLesson?['title'] as String?,
    lastActivityAt: lastActivityAt,
    nextLessonNumber: nextLessonNumber,
    nextLessonTitle: nextLessonTitle,
    nextStepLabel: nextStepLabel,
    studyDayKeys: studyDayKeys.toList()..sort(),
  );
}

int _pagesReadForLesson(Map<String, dynamic> lesson, int lastPage) {
  final start = (lesson['pdf_start_page'] as num?)?.toInt();
  final end = (lesson['pdf_end_page'] as num?)?.toInt();
  if (start == null || end == null || end < start) {
    return lastPage > 0 ? 1 : 0;
  }
  final totalPages = end - start + 1;
  return (lastPage - start + 1).clamp(0, totalPages).toInt();
}

DateTime? _parseDate(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  return null;
}

DateTime _startOfWeek(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  return local.subtract(Duration(days: local.weekday - DateTime.monday));
}

bool _isSameLocalDay(DateTime? a, DateTime b) {
  if (a == null) return false;
  final local = a.toLocal();
  return local.year == b.year && local.month == b.month && local.day == b.day;
}

bool _isOnOrAfterLocalDay(DateTime? date, DateTime start) {
  if (date == null) return false;
  final local = date.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  return !day.isBefore(start);
}

void _rememberStudyDay(Set<String> keys, DateTime? date) {
  if (date == null) return;
  final local = date.toLocal();
  keys.add(_dayKey(local));
}

String _dayKey(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
