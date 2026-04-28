import '../entities/asset.dart';
import '../entities/book.dart';
import '../entities/lesson.dart';
import '../entities/level.dart';

abstract class CatalogRepository {
  Future<List<Level>> fetchLevels();
  Future<List<Book>> fetchBooksByLevel(String levelCode);
  Future<List<Lesson>> fetchLessons(String bookId);
  Future<Asset?> fetchBookPdf(String bookId);
  Future<Asset?> fetchBookStudyGuide(String bookId);
  Future<Asset?> fetchLessonAudio(String lessonId);
}
