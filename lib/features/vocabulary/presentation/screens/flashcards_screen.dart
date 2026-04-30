import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../catalog/presentation/controllers/catalog_providers.dart';
import '../../domain/entities/vocabulary_term.dart';
import '../controllers/vocabulary_providers.dart';

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
          final vocabularyAsync = ref.watch(
            lessonVocabularyProvider((
              bookId: data.bookId,
              lessonId: data.lesson.id,
            )),
          );
          return vocabularyAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const _FlashcardsEmpty(
              message: 'No se pudo cargar tu vocabulario.',
            ),
            data: (terms) => terms.isEmpty
                ? const _FlashcardsEmpty(
                    message:
                        'Guarda palabras en el lector para practicar flashcards.',
                  )
                : _FlashcardsGame(lessonTitle: data.lesson.title, terms: terms),
          );
        },
      ),
    );
  }
}

class _FlashcardsGame extends StatefulWidget {
  const _FlashcardsGame({required this.lessonTitle, required this.terms});

  final String lessonTitle;
  final List<VocabularyTerm> terms;

  @override
  State<_FlashcardsGame> createState() => _FlashcardsGameState();
}

class _FlashcardsGameState extends State<_FlashcardsGame> {
  late List<VocabularyTerm> _deck;
  var _index = 0;
  var _showBack = false;
  var _known = 0;
  var _review = 0;

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.terms)..shuffle(Random());
  }

  @override
  void didUpdateWidget(covariant _FlashcardsGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terms != widget.terms) {
      _restart();
    }
  }

  void _restart() {
    setState(() {
      _deck = List.of(widget.terms)..shuffle(Random());
      _index = 0;
      _showBack = false;
      _known = 0;
      _review = 0;
    });
  }

  void _answer({required bool known}) {
    if (_index >= _deck.length - 1) {
      setState(() {
        if (known) {
          _known++;
        } else {
          _review++;
        }
        _index = _deck.length;
        _showBack = false;
      });
      return;
    }
    setState(() {
      if (known) {
        _known++;
      } else {
        _review++;
      }
      _index++;
      _showBack = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final finished = _index >= _deck.length;
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
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
                          term: _deck[_index],
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
            ),
          ),
        ),
      ),
    );
  }
}

class _Flashcard extends StatelessWidget {
  const _Flashcard({
    required this.term,
    required this.index,
    required this.total,
    required this.showBack,
    required this.onFlip,
  });

  final VocabularyTerm term;
  final int index;
  final int total;
  final bool showBack;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${index + 1} / $total',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: showBack
                      ? colors.onSecondaryContainer
                      : colors.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Spacer(),
            Text(
              showBack ? 'Meaning · Example · Pronunciation' : term.term,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: showBack
                    ? colors.onSecondaryContainer
                    : colors.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (showBack && term.note != null) ...[
              const SizedBox(height: 16),
              Text(
                term.note!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ],
            const Spacer(),
            Icon(
              showBack ? Icons.touch_app_outlined : Icons.style_outlined,
              color:
                  (showBack
                          ? colors.onSecondaryContainer
                          : colors.onPrimaryContainer)
                      .withValues(alpha: 0.72),
            ),
          ],
        ),
      ),
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
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
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
