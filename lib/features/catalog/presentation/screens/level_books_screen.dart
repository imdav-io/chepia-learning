import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
                  'Aún no hay libros para este nivel. Corre el seed o sube tu contenido.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final book = books[i];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  leading: const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
                  title: Text(book.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: book.description == null ? null : Text(book.description!),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/book/${book.slug}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
