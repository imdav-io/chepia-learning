import 'package:equatable/equatable.dart';

/// Vocabulario curado por lección (catálogo). Lo alimenta el script
/// `scripts/quiz_generator/generate-vocabulary.mjs` y la app lo usa como
/// flashcards por defecto.
class LessonVocabularyTerm extends Equatable {
  const LessonVocabularyTerm({
    required this.id,
    required this.lessonId,
    required this.term,
    required this.meaningEs,
    required this.sortOrder,
    this.exampleEn,
    this.pronunciation,
    this.imageUrl,
    this.imageAlt,
    this.audioStoragePath,
  });

  final String id;
  final String lessonId;
  final String term;
  final String meaningEs;
  final String? exampleEn;
  final String? pronunciation;
  final String? imageUrl;
  final String? imageAlt;
  final String? audioStoragePath;
  final int sortOrder;

  factory LessonVocabularyTerm.fromMap(Map<String, dynamic> map) {
    return LessonVocabularyTerm(
      id: map['id'] as String,
      lessonId: map['lesson_id'] as String,
      term: map['term'] as String,
      meaningEs: map['meaning_es'] as String,
      exampleEn: map['example_en'] as String?,
      pronunciation: map['pronunciation'] as String?,
      imageUrl: map['image_url'] as String?,
      imageAlt: map['image_alt'] as String?,
      audioStoragePath: map['audio_storage_path'] as String?,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    id,
    lessonId,
    term,
    meaningEs,
    exampleEn,
    pronunciation,
    imageUrl,
    imageAlt,
    audioStoragePath,
    sortOrder,
  ];
}
