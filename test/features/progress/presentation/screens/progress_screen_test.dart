import 'package:chepia_learning/features/progress/presentation/controllers/progress_providers.dart';
import 'package:chepia_learning/features/progress/presentation/screens/progress_screen.dart';
import 'package:chepia_learning/l10n/generated/app_localizations.dart';
import 'package:chepia_learning/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Progress screen lays out next action card on wide web size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1728, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressOverviewProvider.overrideWith(
            (_) async => [
              BookProgressOverview(
                bookId: 'book-1',
                bookSlug: 'demo-book',
                bookTitle: 'Demo Book',
                levelName: 'Beginner',
                totalLessons: 30,
                totalAudioLessons: 30,
                readCompleted: 10,
                audioCompleted: 8,
                quizTotal: 30,
                quizPassed: 6,
                quizAttempts: 10,
                quizScore: 8,
                quizAnswered: 10,
                pagesRead: 120,
                pagesToday: 4,
                minutesListened: 80,
                minutesThisWeek: 25,
                lastLessonNumber: 29,
                lastLessonTitle: 'Lesson 29',
                lastActivityAt: DateTime(2026, 5, 6),
                nextLessonNumber: 30,
                nextLessonTitle: 'Lesson 30',
                nextStepLabel: 'Continuar lectura',
                studyDayKeys: const ['2026-05-06'],
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProgressScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Continuar lectura'), findsOneWidget);
    expect(find.text('Abrir'), findsOneWidget);
  });
}
