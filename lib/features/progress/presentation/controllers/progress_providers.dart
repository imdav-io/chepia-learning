import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    required this.bookTitle,
    required this.levelName,
    required this.totalLessons,
    required this.readCompleted,
    required this.audioCompleted,
    required this.quizTotal,
    required this.quizPassed,
    required this.pagesRead,
    required this.minutesListened,
    required this.lastLessonNumber,
    required this.lastLessonTitle,
    required this.lastActivityAt,
  });

  final String bookId;
  final String bookTitle;
  final String levelName;
  final int totalLessons;
  final int readCompleted;
  final int audioCompleted;
  final int quizTotal;
  final int quizPassed;
  final int pagesRead;
  final int minutesListened;
  final int? lastLessonNumber;
  final String? lastLessonTitle;
  final DateTime? lastActivityAt;

  int get completedUnits => readCompleted + audioCompleted + quizPassed;

  int get totalUnits => (totalLessons * 2) + quizTotal;

  double get completionRatio =>
      totalUnits == 0 ? 0 : completedUnits / totalUnits;

  int get completionPercent =>
      (completionRatio * 100).round().clamp(0, 100).toInt();
}

final progressOverviewProvider = FutureProvider<List<BookProgressOverview>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return const [];

  final levelsRes = await client
      .from('levels')
      .select('id, name')
      .order('sort_order');
  final booksRes = await client
      .from('books')
      .select('id, level_id, title')
      .order('sort_order');
  final lessonsRes = await client
      .from('lessons')
      .select('id, book_id, number, title, pdf_start_page, pdf_end_page')
      .order('number');
  final readingRes = await client
      .from('reading_progress')
      .select('lesson_id, last_page, is_completed, updated_at')
      .eq('user_id', userId);
  final audioRes = await client
      .from('audio_progress')
      .select('lesson_id, last_position_sec, is_completed, updated_at')
      .eq('user_id', userId);
  final audioAssetsRes = await client
      .from('assets')
      .select('lesson_id, duration_sec')
      .eq('kind', 'audio');
  final quizzesRes = await client
      .from('quizzes')
      .select('id, lesson_id')
      .eq('kind', 'lesson');
  final attemptsRes = await client
      .from('quiz_attempts')
      .select('quiz_id, passed, started_at, finished_at')
      .eq('user_id', userId);

  final levels = (levelsRes as List).cast<Map<String, dynamic>>();
  final books = (booksRes as List).cast<Map<String, dynamic>>();
  final lessons = (lessonsRes as List).cast<Map<String, dynamic>>();
  final readings = (readingRes as List)
      .cast<Map<String, dynamic>>()
      .map(ReadingProgress.fromMap)
      .toList();
  final audios = (audioRes as List)
      .cast<Map<String, dynamic>>()
      .map(AudioProgress.fromMap)
      .toList();
  final audioAssets = (audioAssetsRes as List).cast<Map<String, dynamic>>();
  final quizzes = (quizzesRes as List).cast<Map<String, dynamic>>();
  final attempts = (attemptsRes as List).cast<Map<String, dynamic>>();

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
  for (final asset in audioAssets) {
    final lessonId = asset['lesson_id'] as String?;
    final duration = (asset['duration_sec'] as num?)?.toInt();
    if (lessonId != null && duration != null && duration > 0) {
      audioDurationByLesson[lessonId] = duration;
    }
  }

  final quizLessonById = <String, String>{};
  final quizIdsByBook = <String, Set<String>>{};
  for (final quiz in quizzes) {
    final quizId = quiz['id'] as String;
    final lessonId = quiz['lesson_id'] as String;
    final bookId = lessonBookById[lessonId];
    quizLessonById[quizId] = lessonId;
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
        levelName: levelNameById[book['level_id'] as String] ?? '',
        lessons: lessonsByBook[book['id'] as String] ?? const [],
        readingByLesson: readingByLesson,
        audioByLesson: audioByLesson,
        audioDurationByLesson: audioDurationByLesson,
        quizIds: quizIdsByBook[book['id'] as String] ?? const <String>{},
        passedQuizIds: passedQuizIds,
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
  required Set<String> quizIds,
  required Set<String> passedQuizIds,
  required Map<String, DateTime> latestActivityByLesson,
  required Map<String, Map<String, dynamic>> lessonById,
}) {
  var readCompleted = 0;
  var audioCompleted = 0;
  var pagesRead = 0;
  var secondsListened = 0;
  String? lastLessonId;
  DateTime? lastActivityAt;

  for (final lesson in lessons) {
    final lessonId = lesson['id'] as String;
    final reading = readingByLesson[lessonId];
    if (reading != null) {
      if (reading.isCompleted) readCompleted++;
      pagesRead += _pagesReadForLesson(lesson, reading.lastPage);
    }

    final audio = audioByLesson[lessonId];
    if (audio != null) {
      if (audio.isCompleted) audioCompleted++;
      final duration = audioDurationByLesson[lessonId];
      secondsListened += duration == null
          ? audio.lastPositionSec
          : audio.lastPositionSec.clamp(0, duration).toInt();
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

  return BookProgressOverview(
    bookId: book['id'] as String,
    bookTitle: book['title'] as String,
    levelName: levelName,
    totalLessons: lessons.length,
    readCompleted: readCompleted,
    audioCompleted: audioCompleted,
    quizTotal: quizIds.length,
    quizPassed: quizPassed,
    pagesRead: pagesRead,
    minutesListened: (secondsListened / 60).round(),
    lastLessonNumber: (lastLesson?['number'] as num?)?.toInt(),
    lastLessonTitle: lastLesson?['title'] as String?,
    lastActivityAt: lastActivityAt,
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
