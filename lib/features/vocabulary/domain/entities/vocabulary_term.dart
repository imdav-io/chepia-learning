import 'package:equatable/equatable.dart';

class VocabularyTerm extends Equatable {
  const VocabularyTerm({
    required this.id,
    required this.bookId,
    required this.term,
    required this.createdAt,
    required this.updatedAt,
    this.reviewState = VocabularyReviewState.newTerm,
    this.reviewCount = 0,
    this.intervalDays = 0,
    this.lessonId,
    this.note,
    this.dueAt,
    this.lastReviewedAt,
  });

  final String id;
  final String bookId;
  final String? lessonId;
  final String term;
  final String? note;
  final VocabularyReviewState reviewState;
  final int reviewCount;
  final int intervalDays;
  final DateTime? dueAt;
  final DateTime? lastReviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory VocabularyTerm.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.tryParse(map['created_at'] as String? ?? '');
    final updatedAt = DateTime.tryParse(map['updated_at'] as String? ?? '');
    final dueAt = DateTime.tryParse(map['due_at'] as String? ?? '');
    final lastReviewedAt = DateTime.tryParse(
      map['last_reviewed_at'] as String? ?? '',
    );
    final now = DateTime.now();
    return VocabularyTerm(
      id: map['id'] as String,
      bookId: map['book_id'] as String,
      lessonId: map['lesson_id'] as String?,
      term: map['term'] as String,
      note: map['note'] as String?,
      reviewState: VocabularyReviewStateX.fromDb(
        map['review_state'] as String?,
      ),
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      intervalDays: (map['interval_days'] as num?)?.toInt() ?? 0,
      dueAt: dueAt,
      lastReviewedAt: lastReviewedAt,
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
    reviewState,
    reviewCount,
    intervalDays,
    dueAt,
    lastReviewedAt,
    createdAt,
    updatedAt,
  ];
}

enum VocabularyReviewState { newTerm, learning, mastered }

extension VocabularyReviewStateX on VocabularyReviewState {
  String get dbValue {
    switch (this) {
      case VocabularyReviewState.newTerm:
        return 'new';
      case VocabularyReviewState.learning:
        return 'learning';
      case VocabularyReviewState.mastered:
        return 'mastered';
    }
  }

  String get label {
    switch (this) {
      case VocabularyReviewState.newTerm:
        return 'Nueva';
      case VocabularyReviewState.learning:
        return 'Aprendiendo';
      case VocabularyReviewState.mastered:
        return 'Dominada';
    }
  }

  static VocabularyReviewState fromDb(String? value) {
    switch (value) {
      case 'learning':
        return VocabularyReviewState.learning;
      case 'mastered':
        return VocabularyReviewState.mastered;
      case 'new':
      default:
        return VocabularyReviewState.newTerm;
    }
  }
}
