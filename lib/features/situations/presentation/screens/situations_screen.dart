import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/app_state_views.dart';
import '../../../lesson/presentation/widgets/content_loading_view.dart';
import '../../domain/entities/daily_life_situation.dart';
import '../controllers/daily_life_providers.dart';

enum _SituationGroup { dailyLife, interviews }

class SituationsScreen extends ConsumerStatefulWidget {
  const SituationsScreen({super.key});

  @override
  ConsumerState<SituationsScreen> createState() => _SituationsScreenState();
}

class _SituationsScreenState extends ConsumerState<SituationsScreen> {
  _SituationGroup? _selectedGroup;

  Future<void> _refresh() async {
    ref.invalidate(dailyLifeSituationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final situationsAsync = ref.watch(dailyLifeSituationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_selectedGroup) {
          _SituationGroup.dailyLife => 'Vida diaria',
          _SituationGroup.interviews => 'Entrevistas',
          null => 'Situaciones',
        }),
        leading: _selectedGroup == null
            ? null
            : IconButton(
                tooltip: 'Categorías',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _selectedGroup = null),
              ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: situationsAsync.when(
          loading: () =>
              const ContentLoadingView(status: 'Cargando expresiones...'),
          error: (error, _) => AppErrorView(
            title: 'No pudimos cargar situaciones',
            message:
                'Revisa conexión, permisos o que la migración de situaciones esté aplicada. Detalle: $error',
            onRetry: () => ref.invalidate(dailyLifeSituationsProvider),
          ),
          data: (situations) {
            if (situations.isEmpty) {
              return const AppEmptyView(
                title: 'Aún no hay situaciones',
                message:
                    'Genera contenido con scripts/quiz_generator/generate-situations.mjs para estudiar situaciones y entrevistas.',
                actionLabel: 'Abrir biblioteca',
                icon: Icons.record_voice_over_outlined,
              );
            }

            final dailyLife = situations
                .where((situation) => !situation.isTechnicalInterview)
                .toList();
            final interviews = situations
                .where((situation) => situation.isTechnicalInterview)
                .toList();

            final selected = _selectedGroup;
            if (selected == null) {
              return _SituationGroupChooser(
                dailyLifeCount: dailyLife.length,
                interviewCount: interviews.length,
                expressionCount: dailyLife.fold<int>(
                  0,
                  (sum, situation) => sum + situation.expressionCount,
                ),
                technicalQuestionCount: interviews.fold<int>(
                  0,
                  (sum, situation) => sum + situation.expressionCount,
                ),
                onDailyLife: dailyLife.isEmpty
                    ? null
                    : () => setState(
                        () => _selectedGroup = _SituationGroup.dailyLife,
                      ),
                onInterviews: interviews.isEmpty
                    ? null
                    : () => setState(
                        () => _selectedGroup = _SituationGroup.interviews,
                      ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _SituationSection(
                  title: selected == _SituationGroup.dailyLife
                      ? 'Vida diaria'
                      : 'Entrevistas',
                  subtitle: selected == _SituationGroup.dailyLife
                      ? 'Expresiones naturales por contexto cotidiano.'
                      : 'Preguntas técnicas con respuestas para practicar.',
                  icon: selected == _SituationGroup.dailyLife
                      ? Icons.record_voice_over_outlined
                      : Icons.work_outline,
                  situations: selected == _SituationGroup.dailyLife
                      ? dailyLife
                      : interviews,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SituationGroupChooser extends StatelessWidget {
  const _SituationGroupChooser({
    required this.dailyLifeCount,
    required this.interviewCount,
    required this.expressionCount,
    required this.technicalQuestionCount,
    required this.onDailyLife,
    required this.onInterviews,
  });

  final int dailyLifeCount;
  final int interviewCount;
  final int expressionCount;
  final int technicalQuestionCount;
  final VoidCallback? onDailyLife;
  final VoidCallback? onInterviews;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final children = [
              _SituationEntryButton(
                title: 'Vida diaria',
                subtitle: 'Frases reales para moverte en situaciones comunes.',
                icon: Icons.record_voice_over_outlined,
                accent: colors.secondary,
                countLabel: '$dailyLifeCount situaciones',
                detailLabel: '$expressionCount expresiones',
                onTap: onDailyLife,
              ),
              _SituationEntryButton(
                title: 'Entrevistas',
                subtitle:
                    'Preguntas técnicas en inglés con respuestas de estudio.',
                icon: Icons.work_outline,
                accent: colors.primary,
                countLabel: '$interviewCount temas',
                detailLabel: '$technicalQuestionCount preguntas',
                onTap: onInterviews,
              ),
            ];
            if (!isWide) {
              return Column(
                children: [
                  children.first,
                  const SizedBox(height: 14),
                  children.last,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children.first),
                const SizedBox(width: 14),
                Expanded(child: children.last),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SituationEntryButton extends StatelessWidget {
  const _SituationEntryButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.countLabel,
    required this.detailLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String countLabel;
  final String detailLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 190),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: 0.32)),
                ),
                child: Icon(icon, color: accent, size: 30),
              ),
              const SizedBox(height: 30),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(label: countLabel),
                  _Chip(label: detailLabel),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.arrow_forward_rounded, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SituationSection extends StatelessWidget {
  const _SituationSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.situations,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<DailyLifeSituation> situations;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.24),
                ),
              ),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _Chip(label: '${situations.length} temas'),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            if (!isWide) {
              return Column(
                children: [
                  for (final situation in situations) ...[
                    _SituationCard(
                      situation: situation,
                      onTap: () =>
                          context.push('/situations/${situation.slug}'),
                    ),
                    if (situation != situations.last)
                      const SizedBox(height: 12),
                  ],
                ],
              );
            }

            final cardWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final situation in situations)
                  SizedBox(
                    width: cardWidth,
                    child: _SituationCard(
                      situation: situation,
                      onTap: () =>
                          context.push('/situations/${situation.slug}'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SituationCard extends StatelessWidget {
  const _SituationCard({required this.situation, required this.onTap});

  final DailyLifeSituation situation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _accentFor(situation.sortOrder, colors);
    final countLabel = situation.isTechnicalInterview
        ? '${situation.expressionCount} preguntas técnicas'
        : '${situation.expressionCount} expresiones';
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.42)),
                ),
                child: Icon(_iconFor(situation.icon), color: accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      situation.titleEs,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      situation.titleEn,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(label: situation.levelBand),
                        _Chip(label: countLabel),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

Color _accentFor(int index, ColorScheme colors) {
  switch (index % 4) {
    case 0:
      return colors.primary;
    case 1:
      return colors.secondary;
    case 2:
      return colors.tertiary;
    default:
      return const Color(0xFF22C55E);
  }
}

IconData _iconFor(String icon) {
  switch (icon) {
    case 'cart':
      return Icons.shopping_cart_outlined;
    case 'movie':
      return Icons.movie_outlined;
    case 'home':
      return Icons.home_outlined;
    case 'gym':
      return Icons.fitness_center_outlined;
    case 'restaurant':
      return Icons.restaurant_outlined;
    case 'travel':
      return Icons.flight_takeoff_outlined;
    case 'work':
      return Icons.work_outline;
    case 'code':
      return Icons.code;
    case 'database':
      return Icons.storage_outlined;
    case 'cloud':
      return Icons.cloud_outlined;
    case 'queue':
      return Icons.hub_outlined;
    case 'security':
      return Icons.security_outlined;
    case 'web':
      return Icons.web_outlined;
    case 'ai':
      return Icons.psychology_outlined;
    case 'health':
      return Icons.local_pharmacy_outlined;
    case 'directions':
      return Icons.map_outlined;
    case 'phone':
      return Icons.phone_in_talk_outlined;
    default:
      return Icons.chat_bubble_outline;
  }
}
