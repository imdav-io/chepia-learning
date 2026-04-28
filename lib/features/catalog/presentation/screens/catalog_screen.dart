import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(levelsProvider),
          ),
          data: (levels) {
            if (levels.isEmpty) {
              return const _EmptyView(message: 'Aún no hay niveles disponibles.');
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: levels.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final level = levels[i];
                final color = _colorForCode(level.code);
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    leading: CircleAvatar(
                      backgroundColor: color,
                      child: Text('${level.sortOrder}', style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(_localizedName(level.code, t),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(level.code),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/levels/${level.code}'),
                  ),
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
