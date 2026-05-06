import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../lesson/presentation/widgets/content_loading_view.dart';
import '../controllers/catalog_providers.dart';

class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final levelsAsync = ref.watch(levelsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.catalogTitle)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(levelsProvider),
        child: levelsAsync.when(
          loading: () =>
              const ContentLoadingView(status: 'Cargando niveles...'),
          error: (e, _) => _ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(levelsProvider),
          ),
          data: (levels) {
            if (levels.isEmpty) {
              return const _EmptyView(
                message: 'Aún no hay niveles disponibles.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: levels.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, i) {
                final level = levels[i];
                return _LevelCard(
                  title: _localizedName(level.code, t),
                  code: level.code,
                  number: level.sortOrder,
                  accent: _colorForCode(level.code),
                  onTap: () => context.push('/levels/${level.code}'),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Color _colorForCode(String code) {
    switch (code) {
      case 'beginner':
        return const Color(0xFF22C55E);
      case 'intermediate':
        return const Color(0xFFF59E0B);
      case 'advanced':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  String _localizedName(String code, AppLocalizations t) {
    switch (code) {
      case 'beginner':
        return t.levelBeginner;
      case 'intermediate':
        return t.levelIntermediate;
      case 'advanced':
        return t.levelAdvanced;
      default:
        return code;
    }
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.title,
    required this.code,
    required this.number,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String code;
  final int number;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.82),
            colors.primary.withValues(alpha: 0.24),
            colors.tertiary.withValues(alpha: 0.18),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.2),
        child: Material(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(19),
          child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '$number',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          code,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message});
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
