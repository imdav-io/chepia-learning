import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../controllers/progress_providers.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final progressAsync = ref.watch(progressOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.progressTitle)),
      body: progressAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e.toString(), textAlign: TextAlign.center),
          ),
        ),
        data: (books) {
          if (books.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Todavía no hay progreso para mostrar.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final totalPages = books.fold<int>(0, (sum, b) => sum + b.pagesRead);
          final totalMinutes = books.fold<int>(
            0,
            (sum, b) => sum + b.minutesListened,
          );
          final passedQuizzes = books.fold<int>(
            0,
            (sum, b) => sum + b.quizPassed,
          );
          final average =
              books.fold<double>(0, (sum, b) => sum + b.completionRatio) /
              books.length;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(progressOverviewProvider);
              await ref.read(progressOverviewProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _ProgressHeader(
                  completion: average,
                  pagesRead: totalPages,
                  minutesListened: totalMinutes,
                  quizzesPassed: passedQuizzes,
                ),
                const SizedBox(height: 16),
                Text(
                  'Por libro',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...books.map(
                  (book) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BookProgressCard(book: book),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.completion,
    required this.pagesRead,
    required this.minutesListened,
    required this.quizzesPassed,
  });

  final double completion;
  final int pagesRead;
  final int minutesListened;
  final int quizzesPassed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final percent = (completion * 100).round().clamp(0, 100);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Avance general',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$percent%',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(
                    value: completion.clamp(0, 1).toDouble(),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(
                icon: Icons.menu_book_outlined,
                label: 'Páginas',
                value: '$pagesRead',
              ),
              _MetricPill(
                icon: Icons.headphones_outlined,
                label: 'Audio',
                value: _formatMinutes(minutesListened),
              ),
              _MetricPill(
                icon: Icons.check_circle_outline,
                label: 'Quizzes',
                value: '$quizzesPassed',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookProgressCard extends StatelessWidget {
  const _BookProgressCard({required this.book});

  final BookProgressOverview book;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lastLesson = book.lastLessonNumber == null
        ? 'Sin actividad todavía'
        : 'Lesson ${book.lastLessonNumber}: ${book.lastLessonTitle}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.bookTitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (book.levelName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          book.levelName,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                _PercentBadge(percent: book.completionPercent),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: book.completionRatio.clamp(0, 1).toDouble(),
              minHeight: 7,
              borderRadius: BorderRadius.circular(99),
            ),
            const SizedBox(height: 14),
            Text(
              lastLesson,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TinyStat(
                  icon: Icons.library_books_outlined,
                  text: '${book.readCompleted}/${book.totalLessons} leídas',
                ),
                _TinyStat(
                  icon: Icons.volume_up_outlined,
                  text: '${book.audioCompleted}/${book.totalLessons} audios',
                ),
                _TinyStat(
                  icon: Icons.quiz_outlined,
                  text: '${book.quizPassed}/${book.quizTotal} quizzes',
                ),
                _TinyStat(
                  icon: Icons.article_outlined,
                  text: '${book.pagesRead} páginas',
                ),
                _TinyStat(
                  icon: Icons.timer_outlined,
                  text: _formatMinutes(book.minutesListened),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _PercentBadge extends StatelessWidget {
  const _PercentBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percent / 100,
            strokeWidth: 5,
            backgroundColor: colors.surfaceContainerHighest,
          ),
          Text(
            '$percent%',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _TinyStat extends StatelessWidget {
  const _TinyStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

String _formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes.remainder(60);
  if (rest == 0) return '${hours}h';
  return '${hours}h ${rest}m';
}
