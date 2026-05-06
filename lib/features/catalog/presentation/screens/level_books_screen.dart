import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
                  'Aún no hay libros para este nivel. Corre el seed o sube tu contenido.',
                  textAlign: TextAlign.center,
                ),
              ),
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

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.title,
    required this.description,
    required this.index,
    required this.onTap,
  });

  final String title;
  final String? description;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = index.isOdd ? colors.primary : colors.secondary;
    return Card(
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
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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
