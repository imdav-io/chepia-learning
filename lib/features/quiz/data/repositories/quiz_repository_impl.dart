import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/quiz.dart';
import '../../domain/repositories/quiz_repository.dart';

class SupabaseQuizRepository implements QuizRepository {
  SupabaseQuizRepository(this._client);
  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('Sesión no iniciada');
    return id;
  }

  @override
  Future<Quiz?> fetchLessonQuiz(String lessonId) async {
    try {
      final quizRow = await _client
          .from('quizzes')
          .select('id, lesson_id, kind, passing_score')
          .eq('lesson_id', lessonId)
          .eq('kind', 'lesson')
          .maybeSingle();
      if (quizRow == null) return null;

      final quizId = quizRow['id'] as String;

      final questionRows = await _client
          .from('questions')
          .select('id, prompt, kind, audio_asset_id, explanation, sort_order')
          .eq('quiz_id', quizId)
          .order('sort_order');

      if ((questionRows as List).isEmpty) {
        return Quiz(
          id: quizId,
          lessonId: lessonId,
          kind: 'lesson',
          passingScore: (quizRow['passing_score'] as num?)?.toInt() ?? 70,
          questions: const [],
        );
      }

      final questionIds = questionRows
          .map((q) => (q as Map)['id'] as String)
          .toList(growable: false);

      final optionRows = await _client
          .from('options')
          .select('id, question_id, text, is_correct, sort_order')
          .inFilter('question_id', questionIds)
          .order('sort_order');

      final optionsByQ = <String, List<QuizOption>>{};
      for (final raw in (optionRows as List).cast<Map<String, dynamic>>()) {
        final qId = raw['question_id'] as String;
        optionsByQ.putIfAbsent(qId, () => []).add(QuizOption.fromMap(raw));
      }

      final questions = questionRows.cast<Map<String, dynamic>>().map((m) {
        final id = m['id'] as String;
        final opts = (optionsByQ[id] ?? const <QuizOption>[])
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return QuizQuestion(
          id: id,
          prompt: m['prompt'] as String,
          kind: parseQuestionKind(m['kind'] as String),
          options: opts,
          explanation: m['explanation'] as String?,
          audioAssetId: m['audio_asset_id'] as String?,
          sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      return Quiz(
        id: quizId,
        lessonId: lessonId,
        kind: 'lesson',
        passingScore: (quizRow['passing_score'] as num?)?.toInt() ?? 70,
        questions: questions,
      );
    } catch (e, st) {
      AppLogger.error('fetchLessonQuiz failed', e, st);
      throw ServerFailure('No se pudo cargar el quiz', cause: e);
    }
  }

  @override
  Future<String> startAttempt({required String quizId}) async {
    try {
      final res = await _client
          .from('quiz_attempts')
          .insert({
            'user_id': _userId,
            'quiz_id': quizId,
            'started_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();
      return res['id'] as String;
    } catch (e, st) {
      AppLogger.error('startAttempt failed', e, st);
      throw ServerFailure('No se pudo iniciar el quiz', cause: e);
    }
  }

  @override
  Future<void> recordAnswer({
    required String attemptId,
    required String questionId,
    String? optionId,
    String? textAnswer,
    required bool isCorrect,
  }) async {
    try {
      final payload = <String, dynamic>{
        'attempt_id': attemptId,
        'question_id': questionId,
        'is_correct': isCorrect,
      };
      if (optionId != null) payload['option_id'] = optionId;
      if (textAnswer != null) payload['text_answer'] = textAnswer;
      await _client.from('quiz_answers').upsert(payload);
    } catch (e, st) {
      AppLogger.warn('recordAnswer failed', e, st);
    }
  }

  @override
  Future<QuizAttemptResult> finishAttempt({
    required String attemptId,
    required int score,
    required int total,
    required int passingScore,
  }) async {
    try {
      final percentage = total == 0 ? 0 : ((score * 100) ~/ total);
      final passed = percentage >= passingScore;
      await _client
          .from('quiz_attempts')
          .update({
            'score': score,
            'total': total,
            'passed': passed,
            'finished_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', attemptId);
      return QuizAttemptResult(
        attemptId: attemptId,
        score: score,
        total: total,
        passed: passed,
      );
    } catch (e, st) {
      AppLogger.error('finishAttempt failed', e, st);
      throw ServerFailure('No se pudo guardar el resultado', cause: e);
    }
  }
}
