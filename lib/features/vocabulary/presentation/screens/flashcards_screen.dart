import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../../catalog/presentation/controllers/catalog_providers.dart';
import '../../../lesson/presentation/widgets/content_loading_view.dart';
import '../../../../shared/services/speech_service.dart';
import '../../../../shared/services/tts_service.dart';
import '../../../../shared/widgets/app_state_views.dart';
import '../../domain/entities/lesson_vocabulary_term.dart';
import '../../domain/entities/vocabulary_term.dart';
import '../controllers/vocabulary_providers.dart';

/// Modelo unificado para que el deck pueda mezclar vocabulario curado de la
/// lección y el vocabulario personal que el usuario guardó mientras leía.
class _FlashcardData {
  const _FlashcardData({
    required this.id,
    required this.term,
    this.meaning,
    this.example,
    this.pronunciation,
    this.note,
    this.imageUrl,
    this.imageAlt,
    this.audioStoragePath,
    this.isCurated = false,
  });

  final String id;
  final String term;
  final String? meaning;
  final String? example;
  final String? pronunciation;
  final String? note;
  final String? imageUrl;
  final String? imageAlt;
  final String? audioStoragePath;
  final bool isCurated;

  bool get hasBackContent =>
      meaning != null ||
      example != null ||
      pronunciation != null ||
      note != null;

  factory _FlashcardData.fromCurated(LessonVocabularyTerm t) => _FlashcardData(
    id: t.id,
    term: t.term,
    meaning: t.meaningEs,
    example: t.exampleEn,
    pronunciation: t.pronunciation,
    imageUrl: t.imageUrl,
    imageAlt: t.imageAlt,
    audioStoragePath: t.audioStoragePath,
    isCurated: true,
  );

  factory _FlashcardData.fromUser(VocabularyTerm t) =>
      _FlashcardData(id: t.id, term: t.term, note: t.note);
}

enum _DeckSource { lesson, personal }

class FlashcardsScreen extends ConsumerWidget {
  const FlashcardsScreen({
    super.key,
    required this.bookSlug,
    required this.lessonNumber,
  });

  final String bookSlug;
  final int lessonNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonAsync = ref.watch(
      lessonByBookSlugAndNumberProvider((
        bookSlug: bookSlug,
        lessonNumber: lessonNumber,
      )),
    );

    return Scaffold(
      appBar: AppBar(title: Text('Flashcards · Lesson $lessonNumber')),
      body: lessonAsync.when(
        loading: () =>
            const ContentLoadingView(status: 'Barajando flashcards...'),
        error: (e, _) => AppErrorView(
          title: 'No se pudieron abrir las flashcards',
          message:
              'Revisa que exista la lección y que las tablas de vocabulario estén migradas. Detalle: $e',
          onRetry: () => ref.invalidate(
            lessonByBookSlugAndNumberProvider((
              bookSlug: bookSlug,
              lessonNumber: lessonNumber,
            )),
          ),
        ),
        data: (data) {
          final curatedAsync = ref.watch(
            curatedLessonVocabularyProvider(data.lesson.id),
          );
          final personalAsync = ref.watch(
            lessonVocabularyProvider((
              bookId: data.bookId,
              lessonId: data.lesson.id,
            )),
          );

          if (curatedAsync.isLoading || personalAsync.isLoading) {
            return const ContentLoadingView(status: 'Barajando flashcards...');
          }

          final curated = curatedAsync.valueOrNull ?? const [];
          final personal = personalAsync.valueOrNull ?? const [];

          if (curated.isEmpty && personal.isEmpty) {
            return const AppEmptyView(
              title: 'Sin vocabulario todavía',
              message:
                  'Guarda palabras desde el lector o genera vocabulario desde el panel de contenido.',
              icon: Icons.style_outlined,
            );
          }

          return _FlashcardsRoot(
            bookId: data.bookId,
            lessonId: data.lesson.id,
            lessonTitle: data.lesson.title,
            curated: curated,
            personal: personal,
          );
        },
      ),
    );
  }
}

class _FlashcardsRoot extends StatefulWidget {
  const _FlashcardsRoot({
    required this.bookId,
    required this.lessonId,
    required this.lessonTitle,
    required this.curated,
    required this.personal,
  });

  final String bookId;
  final String lessonId;
  final String lessonTitle;
  final List<LessonVocabularyTerm> curated;
  final List<VocabularyTerm> personal;

  @override
  State<_FlashcardsRoot> createState() => _FlashcardsRootState();
}

class _FlashcardsRootState extends State<_FlashcardsRoot> {
  late _DeckSource _source;

  @override
  void initState() {
    super.initState();
    _source = widget.curated.isNotEmpty
        ? _DeckSource.lesson
        : _DeckSource.personal;
  }

  List<_FlashcardData> get _activeDeck {
    switch (_source) {
      case _DeckSource.lesson:
        return widget.curated.map(_FlashcardData.fromCurated).toList();
      case _DeckSource.personal:
        return widget.personal.map(_FlashcardData.fromUser).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBoth = widget.curated.isNotEmpty && widget.personal.isNotEmpty;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasBoth) ...[
                  SegmentedButton<_DeckSource>(
                    segments: const [
                      ButtonSegment(
                        value: _DeckSource.lesson,
                        label: Text('De la lección'),
                        icon: Icon(Icons.menu_book_outlined),
                      ),
                      ButtonSegment(
                        value: _DeckSource.personal,
                        label: Text('Mis palabras'),
                        icon: Icon(Icons.bookmark_border),
                      ),
                    ],
                    selected: {_source},
                    onSelectionChanged: (s) =>
                        setState(() => _source = s.first),
                  ),
                  const SizedBox(height: 16),
                ],
                Expanded(
                  child: _FlashcardsGame(
                    key: ValueKey('${_source.name}-${_activeDeck.length}'),
                    bookId: widget.bookId,
                    lessonId: widget.lessonId,
                    lessonTitle: widget.lessonTitle,
                    cards: _activeDeck,
                    sourceLabel: _source == _DeckSource.lesson
                        ? 'Vocabulario de la lección'
                        : 'Tu vocabulario guardado',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlashcardsGame extends ConsumerStatefulWidget {
  const _FlashcardsGame({
    super.key,
    required this.bookId,
    required this.lessonId,
    required this.lessonTitle,
    required this.cards,
    required this.sourceLabel,
  });

  final String bookId;
  final String lessonId;
  final String lessonTitle;
  final List<_FlashcardData> cards;
  final String sourceLabel;

  @override
  ConsumerState<_FlashcardsGame> createState() => _FlashcardsGameState();
}

class _FlashcardsGameState extends ConsumerState<_FlashcardsGame> {
  late List<_FlashcardData> _deck;
  late String _deckSignature;
  var _index = 0;
  var _showBack = false;
  // Tracks the highest signal we've inferred for each card in this session:
  // false = visto pero no dominado, true = dominada (pron. score >= 0.85).
  // Evita degradar de dominada → vista al volver con Anterior/Siguiente.
  final _autoMarked = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.cards)..shuffle(Random());
    _deckSignature = _signatureFor(widget.cards);
  }

  @override
  void didUpdateWidget(covariant _FlashcardsGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSignature = _signatureFor(widget.cards);
    if (newSignature != _deckSignature) {
      _deckSignature = newSignature;
      _restart();
    }
  }

  String _signatureFor(List<_FlashcardData> cards) =>
      cards.map((c) => c.id).join('|');

  void _restart() {
    setState(() {
      _deck = List.of(widget.cards)..shuffle(Random());
      _index = 0;
      _showBack = false;
      _autoMarked.clear();
    });
  }

  Future<void> _markCard(_FlashcardData card, {required bool known}) async {
    final prev = _autoMarked[card.id];
    if (prev == known) return;
    if (prev == true && !known) return; // no degradamos dominada → visto
    _autoMarked[card.id] = known;
    try {
      await ref
          .read(vocabularyRepositoryProvider)
          .reviewTerm(
            bookId: widget.bookId,
            lessonId: widget.lessonId,
            term: card.term,
            note: card.meaning ?? card.note,
            known: known,
          );
    } catch (_) {
      // Silencioso: el SR es secundario al flujo. No molestamos al usuario.
    }
  }

  void _goTo(int newIndex) {
    if (newIndex < 0 || newIndex >= _deck.length) return;
    if (newIndex > _index && _index < _deck.length) {
      // Avanzando: marca la actual como vista (no dominada).
      _markCard(_deck[_index], known: false);
    }
    setState(() {
      _index = newIndex;
      _showBack = false;
    });
  }

  void _onPronunciationScored(double score) {
    if (_index >= _deck.length) return;
    if (score >= 0.85) {
      _markCard(_deck[_index], known: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final finished = _index >= _deck.length;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.lessonTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          widget.sourceLabel,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: _deck.isEmpty ? 0 : min(_index, _deck.length) / _deck.length,
          minHeight: 8,
          borderRadius: BorderRadius.circular(99),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: finished
              ? _FlashcardsResult(
                  onRestart: _restart,
                  onClose: () => context.pop(),
                )
              : _Flashcard(
                  card: _deck[_index],
                  index: _index,
                  total: _deck.length,
                  showBack: _showBack,
                  onFlip: () => setState(() => _showBack = !_showBack),
                  onPronunciationScored: _onPronunciationScored,
                ),
        ),
        if (!finished) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Anterior',
                onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_index + 1} / ${_deck.length}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Siguiente',
                onPressed: _index < _deck.length - 1
                    ? () => _goTo(_index + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Flashcard extends StatelessWidget {
  const _Flashcard({
    required this.card,
    required this.index,
    required this.total,
    required this.showBack,
    required this.onFlip,
    required this.onPronunciationScored,
  });

  final _FlashcardData card;
  final int index;
  final int total;
  final bool showBack;
  final VoidCallback onFlip;
  final ValueChanged<double> onPronunciationScored;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = showBack
        ? colors.onSecondaryContainer
        : colors.onPrimaryContainer;
    return InkWell(
      onTap: onFlip,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: showBack ? colors.secondaryContainer : colors.primaryContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: showBack
                ? colors.secondary.withValues(alpha: 0.24)
                : colors.primary.withValues(alpha: 0.24),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CardPill(
                        label: showBack ? 'Significado' : 'Palabra',
                        color: fg,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${index + 1} / $total',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (showBack)
              _CardBack(card: card, foreground: fg)
            else
              _CardFront(
                card: card,
                foreground: fg,
                onPronunciationScored: onPronunciationScored,
              ),
            const Spacer(),
            Icon(
              showBack ? Icons.touch_app_outlined : Icons.style_outlined,
              color: fg.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 4),
            Text(
              showBack ? 'Toca para volver' : 'Toca para ver el significado',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: fg.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardPill extends StatelessWidget {
  const _CardPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color.withValues(alpha: 0.82),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({
    required this.card,
    required this.foreground,
    required this.onPronunciationScored,
  });

  final _FlashcardData card;
  final Color foreground;
  final ValueChanged<double> onPronunciationScored;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (card.imageUrl != null && card.imageUrl!.isNotEmpty) ...[
          _VocabImage(url: card.imageUrl!, alt: card.imageAlt ?? card.term),
          const SizedBox(height: 14),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  card.term,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: card.imageUrl == null ? 76 : 64,
                    height: 0.98,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SpeakButton(card: card, usage: 'term', color: foreground),
          ],
        ),
        if (card.pronunciation != null) ...[
          const SizedBox(height: 8),
          Text(
            '/${card.pronunciation}/',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: foreground.withValues(alpha: 0.72),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _PronunciationCoach(
          target: card.term,
          color: foreground,
          onScored: onPronunciationScored,
        ),
      ],
    );
  }
}

class _VocabImage extends StatelessWidget {
  const _VocabImage({required this.url, required this.alt});
  final String url;
  final String alt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 160, maxWidth: 240),
        color: colors.surfaceContainerHighest,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          semanticLabel: alt,
          loadingBuilder: (_, child, p) => p == null
              ? child
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({required this.card, required this.foreground});

  final _FlashcardData card;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final hasMeaning = card.meaning != null && card.meaning!.trim().isNotEmpty;
    final hasExample = card.example != null && card.example!.trim().isNotEmpty;
    final hasNote = card.note != null && card.note!.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasMeaning)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              card.meaning!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
                fontSize: 44,
                height: 1.08,
              ),
            ),
          )
        else
          Text(
            card.term,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
          ),
        if (hasExample) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  '“${card.example!}”',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: foreground.withValues(alpha: 0.86),
                    fontStyle: FontStyle.italic,
                    fontSize: 20,
                    height: 1.32,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _SpeakButton(card: card, usage: 'example', color: foreground),
            ],
          ),
        ],
        if (hasNote) ...[
          const SizedBox(height: 16),
          Text(
            card.note!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foreground.withValues(alpha: 0.86),
            ),
          ),
        ],
        if (!hasMeaning && !hasExample && !hasNote)
          Text(
            'Sin definición todavía. Edita la palabra para agregarla.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foreground.withValues(alpha: 0.7),
            ),
          ),
      ],
    );
  }
}

class _FlashcardsResult extends StatelessWidget {
  const _FlashcardsResult({required this.onRestart, required this.onClose});

  final VoidCallback onRestart;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.emoji_events_outlined,
          size: 80,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Sesión completa',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.shuffle),
              label: const Text('Otra ronda'),
            ),
            OutlinedButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Volver'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SpeakButton extends ConsumerStatefulWidget {
  const _SpeakButton({
    required this.card,
    required this.usage,
    required this.color,
  });

  final _FlashcardData card;
  final String usage;
  final Color color;

  @override
  ConsumerState<_SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends ConsumerState<_SpeakButton> {
  late final AudioPlayer _player;
  Future<void>? _prewarmFuture;
  var _busy = false;
  var _prewarmed = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _prewarmFuture = _prewarm();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String get _text => widget.usage == 'example'
      ? widget.card.example ?? widget.card.term
      : widget.card.term;

  /// Resuelve la signed URL al montar la card y la deja "calentita" en el
  /// player. Cuando el usuario tap el botón, play() es inmediato.
  /// En vocabulario curado también puede generar el audio del término en
  /// background una sola vez; la edge function lo guarda y las siguientes
  /// reproducciones ya salen desde Storage.
  Future<void> _prewarm() async {
    if (!widget.card.isCurated) return;
    if (widget.usage != 'term') return;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      final url = await _resolveUrl(
        useCachedPath: widget.card.audioStoragePath != null,
      );
      if (!mounted) return;
      await _player.setUrl(url);
      if (!mounted) return;
      _prewarmed = true;
    } catch (_) {
      // Silencioso; el tap reintentará vía edge function.
    }
  }

  Future<void> _speak() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!widget.card.isCurated) {
        await ref.read(ttsServiceProvider).speak(_text);
        return;
      }

      if (!_prewarmed && _prewarmFuture != null) {
        try {
          await _prewarmFuture!.timeout(const Duration(milliseconds: 900));
        } catch (_) {
          // Si todavía se está generando, seguimos con el flujo normal.
        }
      }

      // 0) Pre-warm hit: el setUrl ya completó al montar la card, así que el
      //    play es inmediato. Hacemos seek a 0 por si el usuario lo tocó antes.
      if (_prewarmed) {
        try {
          await _player.seek(Duration.zero);
          await _player.play();
          return;
        } catch (_) {
          _prewarmed = false; // forzar reload en los siguientes pasos
        }
      }

      // 1) Intento con cached path (ruta directa a Storage). Si la URL firmada
      //    ya expiró o el archivo se movió, fall through al edge function.
      var played = false;
      try {
        final url = await _resolveUrl(useCachedPath: true);
        played = await _tryPlay(url);
      } catch (_) {
        played = false;
      }

      // 2) Reintento forzando edge function (regenera audio si falta y
      //    devuelve signed URL fresca con TTL de 24h).
      if (!played) {
        final freshUrl = await _resolveUrl(useCachedPath: false);
        played = await _tryPlay(freshUrl);
      }

      if (!played) throw Exception('playback_failed');
    } catch (_) {
      await ref.read(ttsServiceProvider).speak(_text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usando la voz del dispositivo por ahora.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _resolveUrl({required bool useCachedPath}) {
    return ref
        .read(vocabularyRepositoryProvider)
        .resolveCuratedSpeechUrl(
          lessonVocabularyId: widget.card.id,
          usage: widget.usage,
          storagePath: useCachedPath && widget.usage == 'term'
              ? widget.card.audioStoragePath
              : null,
        );
  }

  Future<bool> _tryPlay(String url) async {
    try {
      await _player.stop();
      await _player.setUrl(url);
      await _player.play();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Escuchar',
      icon: _busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.color,
              ),
            )
          : Icon(Icons.volume_up_rounded, color: widget.color),
      onPressed: _busy ? null : _speak,
    );
  }
}

class _PronunciationCoach extends ConsumerStatefulWidget {
  const _PronunciationCoach({
    required this.target,
    required this.color,
    this.onScored,
  });

  final String target;
  final Color color;
  final ValueChanged<double>? onScored;

  @override
  ConsumerState<_PronunciationCoach> createState() =>
      _PronunciationCoachState();
}

class _PronunciationCoachState extends ConsumerState<_PronunciationCoach> {
  bool _busy = false;
  bool _listening = false;
  String? _transcript;
  double? _score;
  String? _error;

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _listening = true;
      _transcript = null;
      _score = null;
      _error = null;
    });

    final service = ref.read(speechServiceProvider);
    final ok = await service.ensureInitialized();
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _listening = false;
        _error = 'No tenemos acceso al micrófono. Revisa permisos.';
      });
      return;
    }

    String latestTranscript = '';
    var receivedFinal = false;
    var resolved = false;
    void finish(String transcript, {required bool timedOut}) {
      if (resolved || !mounted) return;
      resolved = true;
      _resolveResult(transcript, timedOut: timedOut);
    }

    final timeoutTimer = Timer(const Duration(seconds: 10), () async {
      if (receivedFinal || resolved) return;
      await service.stop();
      finish(latestTranscript, timedOut: true);
    });

    try {
      await for (final result in service.listen()) {
        if (!mounted) {
          timeoutTimer.cancel();
          return;
        }
        latestTranscript = result.transcript;
        setState(() => _transcript = result.transcript);
        if (result.finalResult) {
          receivedFinal = true;
          timeoutTimer.cancel();
          finish(result.transcript, timedOut: false);
          return;
        }
      }
      // Stream cerró sin finalResult (motor terminó sin emitirlo).
      if (!receivedFinal && !resolved) {
        timeoutTimer.cancel();
        finish(latestTranscript, timedOut: false);
      }
    } catch (_) {
      timeoutTimer.cancel();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _listening = false;
        _error = 'No pudimos escucharte. Inténtalo de nuevo.';
      });
    }
  }

  void _resolveResult(String transcript, {required bool timedOut}) {
    final clean = transcript.trim();
    if (clean.isEmpty) {
      setState(() {
        _busy = false;
        _listening = false;
        _error = timedOut
            ? 'No te escuché. Acércate al micrófono e intenta de nuevo.'
            : 'No te escuché bien. Inténtalo de nuevo.';
      });
      return;
    }
    final score = pronunciationScore(expected: widget.target, heard: clean);
    setState(() {
      _score = score;
      _listening = false;
      _busy = false;
    });
    widget.onScored?.call(score);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.color;
    final score = _score;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: _listening
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mic_rounded),
          label: Text(_listening ? 'Escuchando...' : 'Pronunciar'),
        ),
        if (_transcript != null) ...[
          const SizedBox(height: 8),
          Text(
            'Te escuché: "${_transcript!}"',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.78)),
          ),
        ],
        if (score != null) ...[
          const SizedBox(height: 6),
          _ScoreBadge(score: score),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pct = (score * 100).round();
    final (color, label) = score >= 0.85
        ? (colors.secondary, '¡Excelente!')
        : score >= 0.6
        ? (colors.tertiary, 'Casi, intenta otra vez.')
        : (colors.error, 'Vuelve a intentarlo, lento y claro.');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        '$pct% · $label',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
