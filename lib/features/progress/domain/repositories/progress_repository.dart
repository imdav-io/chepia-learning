import '../entities/lesson_progress.dart';

abstract class ProgressRepository {
  Future<ReadingProgress?> fetchReading(String lessonId);
  Future<AudioProgress?> fetchAudio(String lessonId);

  Future<List<ReadingProgress>> fetchReadingForBook(String bookId);
  Future<List<AudioProgress>> fetchAudioForBook(String bookId);

  /// Upsert. `markCompleted` se calcula a partir de un threshold (90%).
  Future<void> saveReading({
    required String lessonId,
    required int lastPage,
    bool? isCompleted,
  });

  Future<void> saveAudio({
    required String lessonId,
    required int lastPositionSec,
    bool? isCompleted,
  });
}
