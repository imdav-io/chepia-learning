import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/daily_life_situation.dart';

class DailyLifeRepository {
  DailyLifeRepository(this._client);

  final SupabaseClient _client;

  Future<List<DailyLifeSituation>> fetchSituations() async {
    try {
      final situations = await _client
          .from('daily_life_situations')
          .select(
            'id, slug, title_es, title_en, description_es, level_band, icon, sort_order, content_kind',
          )
          .order('sort_order')
          .order('title_es');

      final rows = (situations as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return const [];

      final ids = rows.map((row) => row['id'] as String).toList();
      final expressionRows = await _client
          .from('daily_life_expressions')
          .select('situation_id')
          .inFilter('situation_id', ids);
      final expressionCounts = <String, int>{};
      for (final row in (expressionRows as List).cast<Map<String, dynamic>>()) {
        final id = row['situation_id'] as String;
        expressionCounts[id] = (expressionCounts[id] ?? 0) + 1;
      }

      final technicalRows = await _client
          .from('technical_interview_questions')
          .select('situation_id')
          .inFilter('situation_id', ids);
      final technicalCounts = <String, int>{};
      for (final row in (technicalRows as List).cast<Map<String, dynamic>>()) {
        final id = row['situation_id'] as String;
        technicalCounts[id] = (technicalCounts[id] ?? 0) + 1;
      }

      return rows
          .map(
            (row) => DailyLifeSituation.fromMap(
              row,
              expressionCount: row['content_kind'] == 'technical_interview'
                  ? technicalCounts[row['id'] as String] ?? 0
                  : expressionCounts[row['id'] as String] ?? 0,
            ),
          )
          .toList();
    } catch (e, st) {
      AppLogger.error('fetchSituations failed', e, st);
      throw ServerFailure('No se pudieron cargar las situaciones', cause: e);
    }
  }

  Future<DailyLifeSituationBundle?> fetchSituation(String slug) async {
    try {
      final situationRow = await _client
          .from('daily_life_situations')
          .select(
            'id, slug, title_es, title_en, description_es, level_band, icon, sort_order, content_kind',
          )
          .eq('slug', slug)
          .maybeSingle();
      if (situationRow == null) return null;

      final situation = DailyLifeSituation.fromMap(situationRow);
      final expressionRows = await _client
          .from('daily_life_expressions')
          .select(
            'id, situation_id, phrase_en, meaning_es, when_to_use_es, tone, example_en, pronunciation, variants, dialogue, sort_order',
          )
          .eq('situation_id', situation.id)
          .order('sort_order');
      final expressions = (expressionRows as List)
          .cast<Map<String, dynamic>>()
          .map(DailyLifeExpression.fromMap)
          .toList();

      final technicalRows = await _client
          .from('technical_interview_questions')
          .select(
            'id, situation_id, question_en, answer_en, answer_es, sample_answer_en, category, difficulty, key_points, follow_up_questions, common_mistakes, tags, sort_order',
          )
          .eq('situation_id', situation.id)
          .order('sort_order');
      final technicalQuestions = (technicalRows as List)
          .cast<Map<String, dynamic>>()
          .map(TechnicalInterviewQuestion.fromMap)
          .toList();

      final questionRows = await _client
          .from('daily_life_practice_questions')
          .select('id, situation_id, prompt, explanation_es, sort_order')
          .eq('situation_id', situation.id)
          .order('sort_order');
      final questionsRaw = (questionRows as List).cast<Map<String, dynamic>>();

      final questionIds = questionsRaw
          .map((row) => row['id'] as String)
          .toList();
      final optionsByQuestion = <String, List<DailyLifePracticeOption>>{};
      if (questionIds.isNotEmpty) {
        final optionRows = await _client
            .from('daily_life_practice_options')
            .select('id, question_id, text, is_correct, sort_order')
            .inFilter('question_id', questionIds)
            .order('sort_order');
        for (final row in (optionRows as List).cast<Map<String, dynamic>>()) {
          final option = DailyLifePracticeOption.fromMap(row);
          optionsByQuestion
              .putIfAbsent(option.questionId, () => [])
              .add(option);
        }
      }

      final questions = questionsRaw.map((row) {
        final id = row['id'] as String;
        return DailyLifePracticeQuestion(
          id: id,
          situationId: row['situation_id'] as String,
          prompt: row['prompt'] as String,
          explanationEs: row['explanation_es'] as String?,
          options: optionsByQuestion[id] ?? const [],
          sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      return DailyLifeSituationBundle(
        situation: situation,
        expressions: expressions,
        technicalQuestions: technicalQuestions,
        questions: questions,
      );
    } catch (e, st) {
      AppLogger.error('fetchSituation failed', e, st);
      throw ServerFailure('No se pudo cargar la situación', cause: e);
    }
  }
}
