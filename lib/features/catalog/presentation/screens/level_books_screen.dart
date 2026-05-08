import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/services/cache_providers.dart';
import '../../../../shared/widgets/app_state_views.dart';
import '../../../lesson/presentation/widgets/content_loading_view.dart';
import '../controllers/catalog_providers.dart';

class LevelBooksScreen extends ConsumerWidget {
  const LevelBooksScreen({super.key, required this.levelCode});
  final String levelCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksByLevelProvider(levelCode));
    return Scaffold(
      appBar: AppBar(title: Text('Libros · $levelCode')),
      body: booksAsync.when(
        loading: () => const ContentLoadingView(status: 'Preparando libros...'),
        error: (e, _) => Center(
          child: AppErrorView(
            title: 'No pudimos cargar los libros',
            message: e.toString(),
            onRetry: () => ref.invalidate(booksByLevelProvider(levelCode)),
          ),
        ),
        data: (books) {
          if (books.isEmpty) {
            return const AppEmptyView(
              title: 'Aún no hay libros',
              message:
                  'Corre el seed o carga contenido desde el panel admin para este nivel.',
              icon: Icons.library_books_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (_, i) {
              final book = books[i];
              return _BookCard(
                title: book.title,
                slug: book.slug,
                description: book.description,
                index: i + 1,
                onTap: () => context.push('/book/${book.slug}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _BookCard extends ConsumerStatefulWidget {
  const _BookCard({
    required this.title,
    required this.slug,
    required this.description,
    required this.index,
    required this.onTap,
  });

  final String title;
  final String slug;
  final String? description;
  final int index;
  final VoidCallback onTap;

  @override
  ConsumerState<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends ConsumerState<_BookCard> {
  var _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final assets = await ref.read(
        bookOfflineAssetsProvider(widget.slug).future,
      );
      final cache = ref.read(assetCacheProvider);
      for (final asset in assets) {
        await cache.getOrDownload(
          key: asset.key,
          url: asset.url,
          kind: asset.kind,
        );
      }
      ref.invalidate(bookOfflineStatusProvider(widget.slug));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = widget.index.isOdd ? colors.primary : colors.secondary;
    final offlineAsync = ref.watch(bookOfflineStatusProvider(widget.slug));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
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
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Icon(Icons.menu_book_outlined, color: accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (widget.description != null &&
                        widget.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 10),
                    offlineAsync.maybeWhen(
                      data: (status) => _OfflineStatusRow(
                        status: status,
                        downloading: _downloading,
                        onDownload: _download,
                      ),
                      loading: () => const _OfflineStatusSkeleton(),
                      orElse: () => Text(
                        'Offline no disponible todavía',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
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

class _OfflineStatusRow extends StatelessWidget {
  const _OfflineStatusRow({
    required this.status,
    required this.downloading,
    required this.onDownload,
  });

  final BookOfflineStatus status;
  final bool downloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = status.isFullyCached
        ? 'Disponible offline'
        : status.hasAnyCached
        ? '${status.cachedAssets}/${status.totalAssets} offline'
        : '${status.totalAssets} archivos para offline';
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: status.isFullyCached
                ? colors.secondary.withValues(alpha: 0.14)
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: status.isFullyCached
                  ? colors.secondary.withValues(alpha: 0.4)
                  : colors.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: status.isFullyCached ? colors.secondary : null,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: downloading || status.totalAssets == 0 ? null : onDownload,
          icon: downloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_for_offline_outlined),
          label: Text(status.isFullyCached ? 'Actualizar' : 'Descargar'),
        ),
      ],
    );
  }
}

class _OfflineStatusSkeleton extends StatelessWidget {
  const _OfflineStatusSkeleton();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Revisando offline...',
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}
