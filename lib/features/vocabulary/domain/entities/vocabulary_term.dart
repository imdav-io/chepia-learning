import 'package:equatable/equatable.dart';

class VocabularyTerm extends Equatable {
  const VocabularyTerm({
    required this.id,
    required this.bookId,
    required this.term,
    required this.createdAt,
    required this.updatedAt,
    this.lessonId,
    this.note,
  });

  final String id;
  final String bookId;
  final String? lessonId;
  final String term;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory VocabularyTerm.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.tryParse(map['created_at'] as String? ?? '');
    final updatedAt = DateTime.tryParse(map['updated_at'] as String? ?? '');
    final now = DateTime.now();
    return VocabularyTerm(
      id: map['id'] as String,
      bookId: map['book_id'] as String,
      lessonId: map['lesson_id'] as String?,
      term: map['term'] as String,
      note: map['note'] as String?,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
    );
  }

  @override
  List<Object?> get props => [
    id,
    bookId,
    lessonId,
    term,
    note,
    createdAt,
    updatedAt,
  ];
}
