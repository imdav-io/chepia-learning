import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/book_prefetch_controller.dart';

/// Banner discreto que aparece arriba del body del reader mientras se
/// descargan los assets en background. Se oculta solo al terminar.
class BookPrefetchBanner extends ConsumerWidget {
  const BookPrefetchBanner({super.key, required this.bookSlug});

  final String bookSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookPrefetchControllerProvider(bookSlug));
    if (!state.shouldShowBanner) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final pending = state.total - state.skipped;
    final done = state.completed + state.failed;
    final label = state.currentLabel == null
        ? 'Preparando para uso sin conexión...'
        : 'Descargando: ${state.currentLabel}';

    return Material(
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_download_outlined,
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$done/$pending',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pending == 0 ? null : done / pending,
                minHeight: 4,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
