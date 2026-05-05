import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../catalog/presentation/controllers/catalog_providers.dart';
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
  });

  final String id;
  final String term;
  final String? meaning;
  final String? example;
  final String? pronunciation;
  final String? note;

  bool get hasBackContent =>
      meaning != null || example != null || pronunciation != null || note != null;

  factory _FlashcardData.fromCurated(LessonVocabularyTerm t) =>
      _FlashcardData(
        id: t.id,
        term: t.term,
        meaning: t.meaningEs,
        example: t.exampleEn,
        pronunciation: t.pronunciation,
      );

  factory _FlashcardData.fromUser(VocabularyTerm t) => _FlashcardData(
        id: t.id,
        term: t.term,
        note: t.note,
      );
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e.toString(), textAlign: TextAlign.center),
          ),
        ),
        data: (data) {
          final curatedAsync =
              ref.watch(curatedLessonVocabularyProvider(data.lesson.id));
          final personalAsync = ref.watch(
            lessonVocabularyProvider((
              bookId: data.bookId,
              lessonId: data.lesson.id,
            )),
          );

          if (curatedAsync.isLoading || personalAsync.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final curated = curatedAsync.valueOrNull ?? const [];
          final personal = personalAsync.valueOrNull ?? const [];

          if (curated.isEmpty && personal.isEmpty) {
            return const _FlashcardsEmpty(
              message:
                  'Aún no hay vocabulario para esta lección. Guarda palabras desde el lector o pide al admin que genere el vocabulario.',
            );
          }

          return _FlashcardsRoot(
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
    required this.lessonTitle,
    required this.curated,
    required this.personal,
  });

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

class _FlashcardsGame extends StatefulWidget {
  const _FlashcardsGame({
    super.key,
    required this.lessonTitle,
    required this.cards,
    required this.sourceLabel,
  });

  final String lessonTitle;
  final List<_FlashcardData> cards;
  final String sourceLabel;

  @override
  State<_FlashcardsGame> createState() => _FlashcardsGameState();
}

class _FlashcardsGameState extends State<_FlashcardsGame> {
  late List<_FlashcardData> _deck;
  var _index = 0;
  var _showBack = false;
  var _known = 0;
  var _review = 0;

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.cards)..shuffle(Random());
  }

  @override
  void didUpdateWidget(covariant _FlashcardsGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cards != widget.cards) {
      _restart();
    }
  }

  void _restart() {
    setState(() {
      _deck = List.of(widget.cards)..shuffle(Random());
      _index = 0;
      _showBack = false;
      _known = 0;
      _review = 0;
    });
  }

  void _answer({required bool known}) {
    setState(() {
      if (known) {
        _known++;
      } else {
        _review++;
      }
      if (_index >= _deck.length - 1) {
        _index = _deck.length;
      } else {
        _index++;
      }
      _showBack = false;
    });
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.sourceLabel,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: _deck.isEmpty
              ? 0
              : min(_index, _deck.length) / _deck.length,
          minHeight: 8,
          borderRadius: BorderRadius.circular(99),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: finished
              ? _FlashcardsResult(
                  known: _known,
                  review: _review,
                  onRestart: _restart,
                  onClose: () => context.pop(),
                )
              : _Flashcard(
                  card: _deck[_index],
                  index: _index,
                  total: _deck.length,
                  showBack: _showBack,
                  onFlip: () => setState(() => _showBack = !_showBack),
                ),
        ),
        if (!finished) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _answer(known: false),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Repasar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _answer(known: true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Lo sé'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Dominadas $_known · Repasar $_review',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
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
  });

  final _FlashcardData card;
  final int index;
  final int total;
  final bool showBack;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = showBack ? colors.onSecondaryContainer : colors.onPrimaryContainer;
    return InkWell(
      onTap: onFlip,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(24),
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
                Text(
                  showBack ? 'Significado' : 'Palabra',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: fg.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                ),
                const Spacer(),
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
              _CardFront(card: card, foreground: fg),
            const Spacer(),
            Icon(
              showBack ? Icons.touch_app_outlined : Icons.style_outlined,
              color: fg.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 4),
            Text(
              showBack ? 'Tocá para volver' : 'Tocá para ver el significado',
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

class _CardFront extends StatelessWidget {
  const _CardFront({required this.card, required this.foreground});

  final _FlashcardData card;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          card.term,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
              ),
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
      ],
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
          Text(
            card.meaning!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          )
        else
          Text(
            card.term,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        if (hasExample) ...[
          const SizedBox(height: 16),
          Text(
            '“${card.example!}”',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: foreground.withValues(alpha: 0.86),
                  fontStyle: FontStyle.italic,
                ),
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
  const _FlashcardsResult({
    required this.known,
    required this.review,
    required this.onRestart,
    required this.onClose,
  });

  final int known;
  final int review;
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
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text('Dominadas $known · Para repasar $review'),
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

class _FlashcardsEmpty extends StatelessWidget {
  const _FlashcardsEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
