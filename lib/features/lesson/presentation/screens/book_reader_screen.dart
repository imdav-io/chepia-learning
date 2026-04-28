import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../catalog/presentation/controllers/catalog_providers.dart';
import '../../../progress/domain/entities/lesson_progress.dart';
import '../../../progress/presentation/controllers/progress_providers.dart';
import '../widgets/audio_player_bar.dart';
import '../widgets/lesson_list_panel.dart';
import '../widgets/lesson_pdf_reader.dart';

const double _kSidebarBreakpoint = 900;
const double _kSidebarWidth = 320;

class BookReaderScreen extends ConsumerStatefulWidget {
  const BookReaderScreen({super.key, required this.bookSlug});
  final String bookSlug;

  @override
  ConsumerState<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends ConsumerState<BookReaderScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  LessonWithAudio? _selected;
  int? _initialPdfPage;
  String? _bookId;
  List<LessonWithAudio> _lessons = const [];
  Timer? _readingDebounce;
  final _lastSavedPages = <String, int>{};

  void _selectLesson(LessonWithAudio l) {
    setState(() {
      _selected = l;
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  void _openQuiz(LessonWithAudio l) {
    context.push('/quiz/${widget.bookSlug}/${l.lesson.number}');
  }

  void _onReadingPageChanged(int page) {
    final selected = _lessonForPage(page) ?? _selected;
    if (selected == null) return;

    final lessonId = selected.lesson.id;
    if (page == _lastSavedPages[lessonId]) return;

    _readingDebounce?.cancel();
    _readingDebounce = Timer(const Duration(seconds: 1), () {
      _lastSavedPages[lessonId] = page;
      final completed = _isReadingComplete(selected, page);
      final bookId = _bookId;
      unawaited(
        ref
            .read(progressRepositoryProvider)
            .saveReading(
              lessonId: lessonId,
              lastPage: page,
              isCompleted: completed ? true : null,
            )
            .then((_) {
              if (!mounted || !completed || bookId == null) return;
              ref.invalidate(bookProgressProvider(bookId));
            }),
      );
    });
  }

  void _onAudioPositionPersist(int positionSec, int? durationSec) {
    final selected = _selected;
    if (selected == null) return;
    final completed = _isAudioComplete(
      positionSec,
      durationSec ?? selected.audio?.durationSec,
    );
    final bookId = _bookId;
    unawaited(
      ref
          .read(progressRepositoryProvider)
          .saveAudio(
            lessonId: selected.lesson.id,
            lastPositionSec: positionSec,
            isCompleted: completed ? true : null,
          )
          .then((_) {
            if (!mounted || !completed || bookId == null) return;
            ref.invalidate(bookProgressProvider(bookId));
          }),
    );
  }

  void _restoreInitialSelection(
    List<LessonWithAudio> lessons,
    BookProgressSummary? progress,
  ) {
    final reading = _latestReadingProgress(
      progress?.byLessonReading.values ?? const <ReadingProgress>[],
    );
    final lesson = reading == null
        ? lessons.first
        : _lessonById(lessons, reading.lessonId) ?? lessons.first;

    _selected = lesson;
    _initialPdfPage = reading?.lastPage ?? lesson.lesson.pdfStartPage;
    if (_initialPdfPage case final page?) {
      _lastSavedPages[lesson.lesson.id] = page;
      _confirmRestoredReadingCompletion(lesson, page);
    }
  }

  void _confirmRestoredReadingCompletion(LessonWithAudio lesson, int page) {
    if (!_isReadingComplete(lesson, page)) return;
    final bookId = _bookId;
    unawaited(
      ref
          .read(progressRepositoryProvider)
          .saveReading(
            lessonId: lesson.lesson.id,
            lastPage: page,
            isCompleted: true,
          )
          .then((_) {
            if (!mounted || bookId == null) return;
            ref.invalidate(bookProgressProvider(bookId));
          }),
    );
  }

  ReadingProgress? _latestReadingProgress(Iterable<ReadingProgress> items) {
    ReadingProgress? latest;
    for (final item in items) {
      if (latest == null) {
        latest = item;
        continue;
      }
      final itemTime = item.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final latestTime =
          latest.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (itemTime.isAfter(latestTime)) {
        latest = item;
      }
    }
    return latest;
  }

  LessonWithAudio? _lessonById(List<LessonWithAudio> lessons, String id) {
    for (final lesson in lessons) {
      if (lesson.lesson.id == id) return lesson;
    }
    return null;
  }

  LessonWithAudio? _lessonForPage(int page) {
    for (final lesson in _lessons) {
      final start = lesson.lesson.pdfStartPage;
      final end = lesson.lesson.pdfEndPage;
      if (start != null && end != null && page >= start && page <= end) {
        return lesson;
      }
    }
    return null;
  }

  bool _isReadingComplete(LessonWithAudio lesson, int page) {
    final start = lesson.lesson.pdfStartPage;
    final end = lesson.lesson.pdfEndPage;
    if (start == null || end == null || end < start) return false;
    final pageCount = end - start + 1;
    final completionPage = start + (pageCount * 0.9).ceil() - 1;
    return page >= completionPage;
  }

  bool _isAudioComplete(int positionSec, int? durationSec) {
    if (durationSec == null || durationSec <= 0) return false;
    return positionSec >= (durationSec * 0.9).ceil();
  }

  @override
  void dispose() {
    _readingDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(bookReaderDataProvider(widget.bookSlug));
    final isWide = MediaQuery.of(context).size.width >= _kSidebarBreakpoint;

    return dataAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e.toString(), textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (data) {
        _bookId = data.bookId;
        _lessons = data.lessons;
        final progressAsync = ref.watch(bookProgressProvider(data.bookId));

        // Auto-seleccionar la última lección leída la primera vez.
        if (_selected == null && data.lessons.isNotEmpty) {
          if (progressAsync.isLoading && progressAsync.valueOrNull == null) {
            return Scaffold(
              appBar: AppBar(title: Text(data.bookTitle)),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          _restoreInitialSelection(data.lessons, progressAsync.valueOrNull);
        }

        final selected = _selected;

        final panel = LessonListPanel(
          title: data.bookTitle,
          lessons: data.lessons,
          selectedLessonId: selected?.lesson.id,
          onLessonTap: _selectLesson,
          onQuizTap: _openQuiz,
          progressByLessonId: progressAsync.maybeWhen(
            data: (s) =>
                s.byLessonAudio.map((k, v) => MapEntry(k, v.isCompleted)),
            orElse: () => const <String, bool>{},
          ),
        );

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: Text(data.bookTitle),
            leading: isWide
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  )
                : null,
          ),
          drawer: isWide ? null : Drawer(child: SafeArea(child: panel)),
          body: Row(
            children: [
              if (isWide) ...[
                SizedBox(
                  width: _kSidebarWidth,
                  child: Material(elevation: 1, child: panel),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            Material(
                              color: Theme.of(context).colorScheme.surface,
                              child: const TabBar(
                                tabs: [
                                  Tab(
                                    icon: Icon(Icons.menu_book_outlined),
                                    text: 'Libro',
                                  ),
                                  Tab(
                                    icon: Icon(Icons.assignment_outlined),
                                    text: 'Study guide',
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  LessonPdfReader(
                                    pdfUrl: data.pdfUrl,
                                    cacheKey: data.pdfKey,
                                    startPage: _initialPdfPage,
                                    onPageChanged: _onReadingPageChanged,
                                    emptyMessage:
                                        'Este libro aún no tiene PDF principal asociado.',
                                  ),
                                  LessonPdfReader(
                                    pdfUrl: data.studyGuideUrl,
                                    cacheKey: data.studyGuideKey,
                                    emptyMessage:
                                        'Este libro aún no tiene study guide asociado.',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AudioPlayerBar(
                      audioUrl: selected?.audioUrl,
                      title: selected == null
                          ? 'Selecciona una lección'
                          : selected.lesson.title,
                      onPositionPersist: _onAudioPositionPersist,
                      restorePositionSec: progressAsync.maybeWhen(
                        data: (s) => selected == null
                            ? null
                            : s
                                  .byLessonAudio[selected.lesson.id]
                                  ?.lastPositionSec,
                        orElse: () => null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
