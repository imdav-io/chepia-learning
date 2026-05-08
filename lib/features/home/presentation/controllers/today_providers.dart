import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../../progress/presentation/controllers/progress_providers.dart';
import '../../../vocabulary/presentation/controllers/vocabulary_providers.dart';

class DueVocabularyReview {
  const DueVocabularyReview({
    required this.bookSlug,
    required this.bookTitle,
    required this.lessonNumber,
    required this.lessonTitle,
    required this.dueCount,
    required this.sampleTerms,
  });

  final String bookSlug;
  final String bookTitle;
  final int lessonNumber;
  final String lessonTitle;
  final int dueCount;
  final List<String> sampleTerms;
}

class TodayPlan {
  const TodayPlan({
    required this.books,
    required this.streakDays,
    required this.pagesToday,
    required this.minutesThisWeek,
    this.continueBook,
    this.quizBook,
    this.vocabularyReview,
  });

  final List<BookProgressOverview> books;
  final BookProgressOverview? continueBook;
  final BookProgressOverview? quizBook;
  final DueVocabularyReview? vocabularyReview;
  final int streakDays;
  final int pagesToday;
  final int minutesThisWeek;

  bool get hasAnyProgress => books.any((book) => book.completedUnits > 0);
}

final todayPlanProvider = FutureProvider<TodayPlan>((ref) async {
  final books = await ref.watch(progressOverviewProvider.future);
  final dueVocabulary = await _fetchDueVocabularyReview(ref);
  final sorted = [...books]..sort(_compareByActivityThenProgress);

  final continueBook = sorted.cast<BookProgressOverview?>().firstWhere(
    (book) =>
        book?.nextLessonNumber != null &&
        book?.nextStepLabel != 'Resolver quiz',
    orElse: () => sorted.cast<BookProgressOverview?>().firstWhere(
      (book) => book?.nextLessonNumber != null,
      orElse: () => sorted.isEmpty ? null : sorted.first,
    ),
  );

  final quizBook = sorted.cast<BookProgressOverview?>().firstWhere(
    (book) =>
        book?.nextLessonNumber != null &&
        book?.nextStepLabel == 'Resolver quiz',
    orElse: () => null,
  );

  final allStudyDays = <String>{};
  var pagesToday = 0;
  var minutesThisWeek = 0;
  for (final book in books) {
    allStudyDays.addAll(book.studyDayKeys);
    pagesToday += book.pagesToday;
    minutesThisWeek += book.minutesThisWeek;
  }

  return TodayPlan(
    books: books,
    continueBook: continueBook,
    quizBook: quizBook,
    vocabularyReview: dueVocabulary,
    streakDays: _streakDays(allStudyDays, DateTime.now()),
    pagesToday: pagesToday,
    minutesThisWeek: minutesThisWeek,
  );
});

int _compareByActivityThenProgress(
  BookProgressOverview a,
  BookProgressOverview b,
) {
  final aTime = a.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final timeCompare = bTime.compareTo(aTime);
  if (timeCompare != 0) return timeCompare;
  return b.completionPercent.compareTo(a.completionPercent);
}

Future<DueVocabularyReview?> _fetchDueVocabularyReview(Ref ref) async {
  final client = ref.watch(supabaseClientProvider);
  final terms = await ref
      .watch(vocabularyRepositoryProvider)
      .fetchDueReviewTerms(limit: 30);
  final due = terms.where((term) => term.lessonId != null).toList();
  if (due.isEmpty) return null;

  Future<List<Map<String, dynamic>>> safeFetch(
    Future<dynamic> Function() run,
  ) async {
    try {
      final res = await run();
      return res is List ? res.cast<Map<String, dynamic>>() : const [];
    } catch (_) {
      return const [];
    }
  }

  final lessonIds = due.map((term) => term.lessonId!).toSet().toList();
  final lessons = await safeFetch(
    () => client
        .from('lessons')
        .select('id, book_id, number, title')
        .inFilter('id', lessonIds),
  );
  if (lessons.isEmpty) return null;

  final lessonById = {for (final lesson in lessons) lesson['id']: lesson};
  final bookIds = lessons
      .map((lesson) => lesson['book_id'] as String?)
      .whereType<String>()
      .toSet()
      .toList();
  final books = bookIds.isEmpty
      ? const <Map<String, dynamic>>[]
      : await safeFetch(
          () => client
              .from('books')
              .select('id, slug, title')
              .inFilter('id', bookIds),
        );
  final bookById = {for (final book in books) book['id']: book};

  final first = due.firstWhere(
    (term) => lessonById.containsKey(term.lessonId),
    orElse: () => due.first,
  );
  final lesson = lessonById[first.lessonId];
  if (lesson == null) return null;
  final lessonId = lesson['id'] as String;
  final book = bookById[lesson['book_id']];
  if (book == null) return null;
  final termsForLesson = due
      .where((term) => term.lessonId == lessonId)
      .map((term) => term.term)
      .take(3)
      .toList();

  return DueVocabularyReview(
    bookSlug: book['slug'] as String,
    bookTitle: book['title'] as String,
    lessonNumber: (lesson['number'] as num?)?.toInt() ?? 1,
    lessonTitle: lesson['title'] as String? ?? 'Lesson',
    dueCount: due.where((term) => term.lessonId == lessonId).length,
    sampleTerms: termsForLesson,
  );
}

int _streakDays(Set<String> dayKeys, DateTime now) {
  if (dayKeys.isEmpty) return 0;
  var cursor = DateTime(now.year, now.month, now.day);
  var streak = 0;
  while (dayKeys.contains(_dayKey(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

String _dayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
