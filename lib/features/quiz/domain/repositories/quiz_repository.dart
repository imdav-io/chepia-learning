import '../entities/quiz.dart';

abstract class QuizRepository {
  /// Trae el quiz `lesson` con sus preguntas y opciones para una lección.
  /// Devuelve null si no hay quiz generado todavía.
  Future<Quiz?> fetchLessonQuiz(String lessonId);

  /// Crea un attempt nuevo y retorna su id.
  Future<String> startAttempt({required String quizId});

  /// Registra una respuesta del attempt.
  Future<void> recordAnswer({
    required String attemptId,
    required String questionId,
    String? optionId,
    String? textAnswer,
    required bool isCorrect,
  });

  /// Finaliza el attempt y devuelve el resultado.
  Future<QuizAttemptResult> finishAttempt({
    required String attemptId,
    required int score,
    required int total,
    required int passingScore,
  });
}
