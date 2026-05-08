import 'package:equatable/equatable.dart';

class Book extends Equatable {
  const Book({
    required this.id,
    required this.levelId,
    required this.title,
    required this.slug,
    this.description,
    this.coverUrl,
    this.language = 'en',
  });

  final String id;
  final String levelId;
  final String title;
  final String slug;
  final String? description;
  final String? coverUrl;
  final String language;

  factory Book.fromMap(Map<String, dynamic> m) => Book(
    id: m['id'] as String,
    levelId: m['level_id'] as String,
    title: m['title'] as String,
    slug: m['slug'] as String,
    description: m['description'] as String?,
    coverUrl: m['cover_url'] as String?,
    language: (m['language'] as String?) ?? 'en',
  );

  @override
  List<Object?> get props => [
    id,
    levelId,
    title,
    slug,
    description,
    coverUrl,
    language,
  ];
}
