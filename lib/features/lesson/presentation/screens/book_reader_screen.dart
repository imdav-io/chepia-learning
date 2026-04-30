import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../catalog/presentation/controllers/catalog_providers.dart';
import '../../../progress/domain/entities/lesson_progress.dart';
import '../../../progress/presentation/controllers/progress_providers.dart';
import '../../../vocabulary/domain/entities/vocabulary_term.dart';
import '../../../vocabulary/presentation/controllers/vocabulary_providers.dart';
import '../../../../shared/services/cache_providers.dart';
import '../widgets/audio_player_bar.dart';
import '../widgets/lesson_list_panel.dart';
import '../widgets/lesson_page_image_reader.dart';
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
  final _vocabularyController = TextEditingController();
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

  void _openFlashcards(LessonWithAudio l) {
    context.push('/flashcards/${widget.bookSlug}/${l.lesson.number}');
  }

  Future<void> _showOfflineSheet(BookReaderData data) async {
    final assets = _offlineAssetsFor(data);
    var downloading = false;
    var downloaded = 0;
    String? currentLabel;
    String? errorMessage;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> downloadAll() async {
              if (downloading) return;
              setSheetState(() {
                downloading = true;
                downloaded = 0;
                currentLabel = null;
                errorMessage = null;
              });
              final cache = ref.read(assetCacheProvider);
              for (final asset in assets) {
                setSheetState(() => currentLabel = asset.label);
                try {
                  await cache.getOrDownload(
                    key: asset.key,
                    url: asset.url,
                    kind: asset.kind,
                  );
                  setSheetState(() => downloaded++);
                } catch (_) {
                  setSheetState(() {
                    errorMessage = 'No se pudo descargar ${asset.label}.';
                  });
                  break;
                }
              }
              setSheetState(() {
                downloading = false;
                currentLabel = null;
              });
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SafeArea(
                top: false,
                child: FutureBuilder<List<bool>>(
                  future: _offlineStatuses(assets),
                  builder: (context, snap) {
                    final statuses =
                        snap.data ?? List<bool>.filled(assets.length, false);
                    final cached = statuses.where((ok) => ok).length;
                    final progress = assets.isEmpty
                        ? 0.0
                        : (downloading ? downloaded : cached) / assets.length;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Modo offline',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          kIsWeb
                              ? 'En web se conserva durante la sesión del navegador. En móvil queda guardado en el dispositivo.'
                              : 'Guarda PDF y audios de este libro en el dispositivo.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: progress.clamp(0, 1).toDouble(),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          downloading
                              ? 'Descargando ${downloaded + 1}/${assets.length}: ${currentLabel ?? ''}'
                              : '$cached/${assets.length} archivos disponibles offline',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: downloading || assets.isEmpty
                              ? null
                              : downloadAll,
                          icon: downloading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_for_offline_outlined),
                          label: Text(
                            cached == assets.length
                                ? 'Actualizar descarga'
                                : 'Descargar todo',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<_OfflineAsset> _offlineAssetsFor(BookReaderData data) {
    final assets = <_OfflineAsset>[];
    if (data.pdfUrl != null && data.pdfKey != null) {
      assets.add(
        _OfflineAsset(
          label: 'PDF principal',
          key: data.pdfKey!,
          url: data.pdfUrl!,
          kind: 'pdf',
        ),
      );
    }
    if (data.studyGuideUrl != null && data.studyGuideKey != null) {
      assets.add(
        _OfflineAsset(
          label: 'Study guide',
          key: data.studyGuideKey!,
          url: data.studyGuideUrl!,
          kind: 'pdf',
        ),
      );
    }
    for (final lesson in data.lessons) {
      final audio = lesson.audio;
      if (audio == null || lesson.audioUrl == null) continue;
      assets.add(
        _OfflineAsset(
          label: 'Audio L${lesson.lesson.number}',
          key: audio.storagePath,
          url: lesson.audioUrl!,
          kind: 'audio',
        ),
      );
    }
    return assets;
  }

  Future<List<bool>> _offlineStatuses(List<_OfflineAsset> assets) async {
    final cache = ref.read(assetCacheProvider);
    final result = <bool>[];
    for (final asset in assets) {
      result.add(await cache.exists(asset.key, kind: asset.kind));
    }
    return result;
  }

  Future<void> _showVocabularySheet(LessonWithAudio lesson) async {
    final bookId = _bookId;
    if (bookId == null) return;
    final params = (bookId: bookId, lessonId: lesson.lesson.id);
    var isSaving = false;
    String? errorMessage;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> addTerm(WidgetRef sheetRef) async {
              final raw = _vocabularyController.text.trim();
              if (raw.isEmpty || isSaving) return;
              setSheetState(() {
                isSaving = true;
                errorMessage = null;
              });
              try {
                await sheetRef
                    .read(vocabularyRepositoryProvider)
                    .saveTerm(
                      bookId: bookId,
                      lessonId: lesson.lesson.id,
                      term: raw,
                    );
                _vocabularyController.clear();
                sheetRef.invalidate(lessonVocabularyProvider(params));
              } catch (_) {
                errorMessage =
                    'No se pudo guardar. Revisa la tabla en Supabase.';
              } finally {
                if (mounted) {
                  setSheetState(() => isSaving = false);
                }
              }
            }

            Future<void> removeTerm(
              WidgetRef sheetRef,
              VocabularyTerm term,
            ) async {
              setSheetState(() => errorMessage = null);
              try {
                await sheetRef
                    .read(vocabularyRepositoryProvider)
                    .deleteTerm(term.id);
                sheetRef.invalidate(lessonVocabularyProvider(params));
              } catch (_) {
                setSheetState(() {
                  errorMessage = 'No se pudo borrar la palabra.';
                });
              }
            }

            return Consumer(
              builder: (context, sheetRef, _) {
                final vocabularyAsync = sheetRef.watch(
                  lessonVocabularyProvider(params),
                );

                return Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Vocabulario de repaso',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lesson ${lesson.lesson.number}: ${lesson.lesson.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _vocabularyController,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Palabra o frase',
                                  prefixIcon: Icon(Icons.translate_outlined),
                                ),
                                onSubmitted: (_) => addTerm(sheetRef),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.filled(
                              onPressed: isSaving
                                  ? null
                                  : () => addTerm(sheetRef),
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.add),
                              tooltip: 'Guardar',
                            ),
                          ],
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        vocabularyAsync.when(
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          error: (_, _) => _VocabularyEmptyState(
                            message:
                                'No se pudo cargar tu vocabulario. Intenta de nuevo.',
                          ),
                          data: (terms) => terms.isEmpty
                              ? const _VocabularyEmptyState(
                                  message:
                                      'Guarda palabras mientras lees para repasarlas antes del quiz.',
                                )
                              : _VocabularyChipList(
                                  terms: terms,
                                  onDeleted: (term) =>
                                      removeTerm(sheetRef, term),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
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
    _vocabularyController.dispose();
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
        final progress = progressAsync.valueOrNull;
        final hasStudyGuide = data.studyGuideUrl != null;
        final selectedRead = selected == null
            ? false
            : progress?.isLessonRead(selected.lesson.id) ?? false;
        final selectedHeard = selected == null
            ? false
            : progress?.isLessonHeard(selected.lesson.id) ?? false;
        final vocabularyCount = selected == null
            ? 0
            : ref
                      .watch(
                        lessonVocabularyProvider((
                          bookId: data.bookId,
                          lessonId: selected.lesson.id,
                        )),
                      )
                      .valueOrNull
                      ?.length ??
                  0;

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
            actions: [
              IconButton(
                icon: const Icon(Icons.download_for_offline_outlined),
                tooltip: 'Modo offline',
                onPressed: () => _showOfflineSheet(data),
              ),
            ],
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
                    if (selected != null)
                      _StudyFlowStrip(
                        lesson: selected,
                        isRead: selectedRead,
                        isHeard: selectedHeard,
                        savedWords: vocabularyCount,
                        onQuizTap: () => _openQuiz(selected),
                        onFlashcardsTap: () => _openFlashcards(selected),
                        onVocabularyTap: () => _showVocabularySheet(selected),
                      ),
                    Expanded(
                      child: hasStudyGuide
                          ? DefaultTabController(
                              length: 2,
                              child: Column(
                                children: [
                                  Material(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
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
                                        _MainBookReader(
                                          data: data,
                                          startPage: _initialPdfPage,
                                          onPageChanged: _onReadingPageChanged,
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
                            )
                          : _MainBookReader(
                              data: data,
                              startPage: _initialPdfPage,
                              onPageChanged: _onReadingPageChanged,
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

class _MainBookReader extends StatelessWidget {
  const _MainBookReader({
    required this.data,
    required this.startPage,
    required this.onPageChanged,
  });

  final BookReaderData data;
  final int? startPage;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final manifestUrl = data.pageManifestUrl;
    final manifestKey = data.pageManifestKey;
    if (manifestUrl != null && manifestKey != null) {
      return LessonPageImageReader(
        manifestUrl: manifestUrl,
        manifestCacheKey: manifestKey,
        startPage: startPage,
        onPageChanged: onPageChanged,
      );
    }
    return LessonPdfReader(
      pdfUrl: data.pdfUrl,
      cacheKey: data.pdfKey,
      startPage: startPage,
      onPageChanged: onPageChanged,
      emptyMessage: 'Este libro aún no tiene PDF principal asociado.',
    );
  }
}

class _StudyFlowStrip extends StatelessWidget {
  const _StudyFlowStrip({
    required this.lesson,
    required this.isRead,
    required this.isHeard,
    required this.savedWords,
    required this.onQuizTap,
    required this.onFlashcardsTap,
    required this.onVocabularyTap,
  });

  final LessonWithAudio lesson;
  final bool isRead;
  final bool isHeard;
  final int savedWords;
  final VoidCallback onQuizTap;
  final VoidCallback onFlashcardsTap;
  final VoidCallback onVocabularyTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: Text('${lesson.lesson.number}'),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      lesson.lesson.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _FlowStepChip(
              icon: Icons.menu_book_outlined,
              label: 'Leer',
              isDone: isRead,
            ),
            _FlowStepChip(
              icon: Icons.headphones_outlined,
              label: 'Escuchar',
              isDone: isHeard,
              isDisabled: !lesson.hasAudio,
            ),
            _FlowStepChip(
              icon: Icons.quiz_outlined,
              label: 'Quiz',
              isDone: false,
              onTap: onQuizTap,
            ),
            _FlowStepChip(
              icon: Icons.style_outlined,
              label: savedWords == 0
                  ? 'Vocabulario'
                  : 'Vocabulario · $savedWords',
              isDone: savedWords > 0,
              onTap: onVocabularyTap,
            ),
            _FlowStepChip(
              icon: Icons.view_carousel_outlined,
              label: 'Flashcards',
              isDone: false,
              isDisabled: savedWords == 0,
              onTap: onFlashcardsTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineAsset {
  const _OfflineAsset({
    required this.label,
    required this.key,
    required this.url,
    required this.kind,
  });

  final String label;
  final String key;
  final String url;
  final String kind;
}

class _VocabularyEmptyState extends StatelessWidget {
  const _VocabularyEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message),
    );
  }
}

class _VocabularyChipList extends StatelessWidget {
  const _VocabularyChipList({required this.terms, required this.onDeleted});

  final List<VocabularyTerm> terms;
  final Future<void> Function(VocabularyTerm term) onDeleted;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final term in terms)
          InputChip(
            label: Text(term.term),
            avatar: const Icon(Icons.style_outlined),
            onDeleted: () => unawaited(onDeleted(term)),
          ),
      ],
    );
  }
}

class _FlowStepChip extends StatelessWidget {
  const _FlowStepChip({
    required this.icon,
    required this.label,
    required this.isDone,
    this.isDisabled = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDone;
  final bool isDisabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = !isDisabled;
    final foreground = isDone
        ? colors.onPrimaryContainer
        : enabled
        ? colors.onSurface
        : colors.onSurfaceVariant.withValues(alpha: 0.58);
    final background = isDone
        ? colors.primaryContainer
        : colors.surfaceContainerHighest.withValues(alpha: enabled ? 1 : 0.56);

    return ActionChip(
      avatar: Icon(isDone ? Icons.check_circle : icon, size: 18),
      label: Text(label),
      onPressed: enabled ? onTap : null,
      backgroundColor: background,
      disabledColor: background,
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      side: BorderSide(
        color: isDone
            ? colors.primary.withValues(alpha: 0.28)
            : Colors.transparent,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
