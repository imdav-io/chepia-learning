import 'package:chepia_learning/features/home/presentation/controllers/today_providers.dart';
import 'package:chepia_learning/features/home/presentation/screens/today_screen.dart';
import 'package:chepia_learning/features/onboarding/presentation/controllers/onboarding_providers.dart';
import 'package:chepia_learning/features/progress/presentation/controllers/progress_providers.dart';
import 'package:chepia_learning/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Today screen shows daily route with no progress on mobile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_todayHarness(_emptyPlan()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Empieza tu ruta'), findsOneWidget);
    expect(find.text('Continúa aquí'), findsOneWidget);
    expect(find.text('Repasa esto'), findsOneWidget);
    expect(find.text('Haz este quiz'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Cómo estudiar hoy'), findsOneWidget);
  });

  testWidgets('Today screen lays out action cards on wide web size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1728, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_todayHarness(_activePlan()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Continuar lectura'), findsOneWidget);
    expect(find.text('Repasar'), findsOneWidget);
    expect(find.text('Resolver'), findsOneWidget);
  });
}

Widget _todayHarness(TodayPlan plan) {
  return ProviderScope(
    overrides: [
      todayPlanProvider.overrideWith((_) async => plan),
      onboardingStateProvider.overrideWith(
        (_) async => const OnboardingState(
          isCompleted: true,
          dailyReminderEnabled: true,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const TodayScreen(),
    ),
  );
}

TodayPlan _emptyPlan() {
  return const TodayPlan(
    books: [],
    streakDays: 0,
    pagesToday: 0,
    minutesThisWeek: 0,
  );
}

TodayPlan _activePlan() {
  final book = BookProgressOverview(
    bookId: 'book-1',
    bookSlug: 'demo-book',
    bookTitle: 'Demo Book',
    levelName: 'Beginner',
    totalLessons: 30,
    totalAudioLessons: 30,
    readCompleted: 3,
    audioCompleted: 2,
    quizTotal: 30,
    quizPassed: 1,
    quizAttempts: 2,
    quizScore: 8,
    quizAnswered: 10,
    pagesRead: 42,
    pagesToday: 4,
    minutesListened: 40,
    minutesThisWeek: 18,
    lastLessonNumber: 2,
    lastLessonTitle: 'Lesson 2',
    lastActivityAt: DateTime(2026, 5, 6),
    nextLessonNumber: 3,
    nextLessonTitle: 'Lesson 3',
    nextStepLabel: 'Continuar lectura',
    studyDayKeys: const ['2026-05-06'],
  );

  final quizBook = BookProgressOverview(
    bookId: 'book-2',
    bookSlug: 'quiz-book',
    bookTitle: 'Quiz Book',
    levelName: 'Beginner',
    totalLessons: 30,
    totalAudioLessons: 30,
    readCompleted: 4,
    audioCompleted: 4,
    quizTotal: 30,
    quizPassed: 3,
    quizAttempts: 3,
    quizScore: 9,
    quizAnswered: 10,
    pagesRead: 54,
    pagesToday: 0,
    minutesListened: 50,
    minutesThisWeek: 10,
    lastLessonNumber: 4,
    lastLessonTitle: 'Lesson 4',
    lastActivityAt: DateTime(2026, 5, 5),
    nextLessonNumber: 4,
    nextLessonTitle: 'Lesson 4',
    nextStepLabel: 'Resolver quiz',
    studyDayKeys: const ['2026-05-05'],
  );

  return TodayPlan(
    books: [book, quizBook],
    continueBook: book,
    quizBook: quizBook,
    vocabularyReview: const DueVocabularyReview(
      bookSlug: 'demo-book',
      bookTitle: 'Demo Book',
      lessonNumber: 3,
      lessonTitle: 'Lesson 3',
      dueCount: 3,
      sampleTerms: ['tired', 'career', 'look for'],
    ),
    streakDays: 1,
    pagesToday: 4,
    minutesThisWeek: 28,
  );
}
