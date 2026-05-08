import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/app_state_views.dart';
import '../../../lesson/presentation/widgets/content_loading_view.dart';
import '../../../onboarding/presentation/controllers/onboarding_providers.dart';
import '../../../progress/presentation/controllers/progress_providers.dart';
import '../controllers/today_providers.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(todayPlanProvider);
    final onboardingAsync = ref.watch(onboardingStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Hoy')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/companion'),
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: const Text('Hablar con Chepia'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(progressOverviewProvider);
          ref.invalidate(todayPlanProvider);
        },
        child: planAsync.when(
          loading: () =>
              const ContentLoadingView(status: 'Armando tu ruta diaria...'),
          error: (_, _) => AppErrorView(
            title: 'No pudimos preparar tu ruta',
            message:
                'La app no pudo leer tu progreso. Revisa conexión, sesión o permisos de Supabase.',
            onRetry: () => ref.invalidate(todayPlanProvider),
          ),
          data: (plan) {
            final onboarding = onboardingAsync.valueOrNull;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _HeroPlanCard(plan: plan),
                const SizedBox(height: 16),
                _ActionGrid(plan: plan),
                const SizedBox(height: 16),
                _HabitCard(
                  plan: plan,
                  reminderEnabled: onboarding?.dailyReminderEnabled ?? true,
                  onReminderChanged: (enabled) async {
                    await ref
                        .read(onboardingPreferencesProvider)
                        .setDailyReminderEnabled(enabled);
                    ref.invalidate(onboardingStateProvider);
                  },
                ),
                const SizedBox(height: 16),
                _StudyFlowCard(
                  onOpenCatalog: () => context.go('/catalog'),
                  onOpenProgress: () => context.go('/progress'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroPlanCard extends StatelessWidget {
  const _HeroPlanCard({required this.plan});

  final TodayPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = plan.continueBook?.nextStepLabel ?? 'Empieza tu ruta';
    final subtitle = plan.continueBook == null
        ? 'Elige un libro para empezar a leer, escuchar y repasar.'
        : '${plan.continueBook!.bookTitle} · Lesson ${plan.continueBook!.nextLessonNumber}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.22),
            colors.surfaceContainerHigh,
            colors.tertiary.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: colors.primary),
              const SizedBox(width: 10),
              Text(
                _todayLabel(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(
                icon: Icons.local_fire_department_outlined,
                label: '${plan.streakDays} días de racha',
              ),
              _MetricPill(
                icon: Icons.menu_book_outlined,
                label: '${plan.pagesToday} páginas hoy',
              ),
              _MetricPill(
                icon: Icons.headphones_outlined,
                label: '${plan.minutesThisWeek} min esta semana',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const weekdays = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    return 'Plan de ${weekdays[now.weekday - 1]}';
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.plan});

  final TodayPlan plan;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _DailyActionCard(
            icon: Icons.play_circle_outline,
            title: 'Continúa aquí',
            body: _continueBody(plan.continueBook),
            actionLabel: 'Abrir',
            accent: Theme.of(context).colorScheme.primary,
            onTap: plan.continueBook == null
                ? () => context.go('/catalog')
                : () => context.push('/book/${plan.continueBook!.bookSlug}'),
          ),
          _DailyActionCard(
            icon: Icons.style_outlined,
            title: 'Repasa esto',
            body: _vocabBody(plan.vocabularyReview),
            actionLabel: plan.vocabularyReview == null
                ? 'Sin pendientes'
                : 'Repasar',
            accent: Theme.of(context).colorScheme.secondary,
            onTap: plan.vocabularyReview == null
                ? null
                : () => context.push(
                    '/flashcards/${plan.vocabularyReview!.bookSlug}/${plan.vocabularyReview!.lessonNumber}',
                  ),
          ),
          _DailyActionCard(
            icon: Icons.quiz_outlined,
            title: 'Haz este quiz',
            body: _quizBody(plan.quizBook),
            actionLabel: plan.quizBook == null ? 'Sin pendientes' : 'Resolver',
            accent: Theme.of(context).colorScheme.tertiary,
            onTap: plan.quizBook == null
                ? null
                : () => context.push(
                    '/quiz/${plan.quizBook!.bookSlug}/${plan.quizBook!.nextLessonNumber}',
                  ),
          ),
        ];

        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (final card in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: card,
                ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i < cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  String _continueBody(BookProgressOverview? book) {
    if (book == null) {
      return 'Abre la biblioteca y empieza tu primer libro.';
    }
    return '${book.bookTitle}\nLesson ${book.nextLessonNumber}: ${book.nextLessonTitle ?? 'siguiente lección'}';
  }

  String _vocabBody(DueVocabularyReview? review) {
    if (review == null) {
      return 'No tienes palabras vencidas. Guarda vocabulario o repasa una lección.';
    }
    final samples = review.sampleTerms.isEmpty
        ? ''
        : '\n${review.sampleTerms.join(', ')}';
    return '${review.dueCount} palabras listas · ${review.lessonTitle}$samples';
  }

  String _quizBody(BookProgressOverview? book) {
    if (book == null) {
      return 'Cuando termines lectura y audio, aparecerá el siguiente quiz.';
    }
    return '${book.bookTitle}\nLesson ${book.nextLessonNumber}: ${book.nextLessonTitle ?? 'quiz pendiente'}';
  }
}

class _DailyActionCard extends StatelessWidget {
  const _DailyActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 210),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 30),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: onTap == null
                ? OutlinedButton(onPressed: null, child: Text(actionLabel))
                : FilledButton(onPressed: onTap, child: Text(actionLabel)),
          ),
        ],
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.plan,
    required this.reminderEnabled,
    required this.onReminderChanged,
  });

  final TodayPlan plan;
  final bool reminderEnabled;
  final ValueChanged<bool> onReminderChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final needsMinutes = plan.pagesToday == 0 && plan.minutesThisWeek == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: colors.secondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needsMinutes ? 'Te faltan 5 minutos' : 'Hábito activo',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  reminderEnabled
                      ? 'Te mostraremos este recordatorio dentro de la app cada día.'
                      : 'Activa el recordatorio para mantener el ritmo.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch(value: reminderEnabled, onChanged: onReminderChanged),
        ],
      ),
    );
  }
}

class _StudyFlowCard extends StatelessWidget {
  const _StudyFlowCard({
    required this.onOpenCatalog,
    required this.onOpenProgress,
  });

  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenProgress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cómo estudiar hoy',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const _FlowRow(
              icon: Icons.menu_book_outlined,
              title: '1. Lee una lección corta',
              body: 'Avanza aunque sea unas páginas.',
            ),
            const _FlowRow(
              icon: Icons.headphones_outlined,
              title: '2. Escucha el audio',
              body: 'El listening refuerza lo que acabas de leer.',
            ),
            const _FlowRow(
              icon: Icons.style_outlined,
              title: '3. Repasa vocabulario',
              body: 'Las palabras vuelven cuando toca recordarlas.',
            ),
            const _FlowRow(
              icon: Icons.quiz_outlined,
              title: '4. Cierra con quiz',
              body: 'Comprueba comprensión y desbloquea progreso.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenCatalog,
                  icon: const Icon(Icons.library_books_outlined),
                  label: const Text('Biblioteca'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenProgress,
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('Progreso'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
