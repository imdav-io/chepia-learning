import 'package:equatable/equatable.dart';

class DailyLifeSituation extends Equatable {
  const DailyLifeSituation({
    required this.id,
    required this.slug,
    required this.titleEs,
    required this.titleEn,
    required this.levelBand,
    required this.icon,
    required this.sortOrder,
    required this.contentKind,
    this.descriptionEs,
    this.expressionCount = 0,
  });

  final String id;
  final String slug;
  final String titleEs;
  final String titleEn;
  final String? descriptionEs;
  final String levelBand;
  final String icon;
  final int sortOrder;
  final String contentKind;
  final int expressionCount;

  bool get isTechnicalInterview => contentKind == 'technical_interview';

  factory DailyLifeSituation.fromMap(
    Map<String, dynamic> map, {
    int expressionCount = 0,
  }) {
    return DailyLifeSituation(
      id: map['id'] as String,
      slug: map['slug'] as String,
      titleEs: map['title_es'] as String,
      titleEn: map['title_en'] as String,
      descriptionEs: map['description_es'] as String?,
      levelBand: map['level_band'] as String? ?? 'A2-B1',
      icon: map['icon'] as String? ?? 'chat',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      contentKind: map['content_kind'] as String? ?? 'expressions',
      expressionCount: expressionCount,
    );
  }

  @override
  List<Object?> get props => [
    id,
    slug,
    titleEs,
    titleEn,
    descriptionEs,
    levelBand,
    icon,
    sortOrder,
    contentKind,
    expressionCount,
  ];
}

class TechnicalInterviewQuestion extends Equatable {
  const TechnicalInterviewQuestion({
    required this.id,
    required this.situationId,
    required this.questionEn,
    required this.answerEn,
    required this.difficulty,
    required this.keyPoints,
    required this.followUpQuestions,
    required this.commonMistakes,
    required this.tags,
    required this.sortOrder,
    this.answerEs,
    this.sampleAnswerEn,
    this.category,
  });

  final String id;
  final String situationId;
  final String questionEn;
  final String answerEn;
  final String? answerEs;
  final String? sampleAnswerEn;
  final String? category;
  final String difficulty;
  final List<String> keyPoints;
  final List<String> followUpQuestions;
  final List<String> commonMistakes;
  final List<String> tags;
  final int sortOrder;

  factory TechnicalInterviewQuestion.fromMap(Map<String, dynamic> map) {
    return TechnicalInterviewQuestion(
      id: map['id'] as String,
      situationId: map['situation_id'] as String,
      questionEn: map['question_en'] as String,
      answerEn: map['answer_en'] as String,
      answerEs: map['answer_es'] as String?,
      sampleAnswerEn: map['sample_answer_en'] as String?,
      category: map['category'] as String?,
      difficulty: map['difficulty'] as String? ?? 'mid',
      keyPoints: _stringList(map['key_points']),
      followUpQuestions: _stringList(map['follow_up_questions']),
      commonMistakes: _stringList(map['common_mistakes']),
      tags: _stringList(map['tags']),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  static List<String> _stringList(Object? value) {
    return value is List
        ? value.map((item) => item.toString()).toList()
        : const [];
  }

  @override
  List<Object?> get props => [
    id,
    situationId,
    questionEn,
    answerEn,
    answerEs,
    sampleAnswerEn,
    category,
    difficulty,
    keyPoints,
    followUpQuestions,
    commonMistakes,
    tags,
    sortOrder,
  ];
}

class DailyLifeExpression extends Equatable {
  const DailyLifeExpression({
    required this.id,
    required this.situationId,
    required this.phraseEn,
    required this.meaningEs,
    required this.tone,
    required this.variants,
    required this.dialogue,
    required this.sortOrder,
    this.whenToUseEs,
    this.exampleEn,
    this.pronunciation,
  });

  final String id;
  final String situationId;
  final String phraseEn;
  final String meaningEs;
  final String? whenToUseEs;
  final String tone;
  final String? exampleEn;
  final String? pronunciation;
  final List<String> variants;
  final List<DailyLifeDialogueLine> dialogue;
  final int sortOrder;

  factory DailyLifeExpression.fromMap(Map<String, dynamic> map) {
    final rawVariants = map['variants'];
    final rawDialogue = map['dialogue'];
    return DailyLifeExpression(
      id: map['id'] as String,
      situationId: map['situation_id'] as String,
      phraseEn: map['phrase_en'] as String,
      meaningEs: map['meaning_es'] as String,
      whenToUseEs: map['when_to_use_es'] as String?,
      tone: map['tone'] as String? ?? 'neutral',
      exampleEn: map['example_en'] as String?,
      pronunciation: map['pronunciation'] as String?,
      variants: rawVariants is List
          ? rawVariants.map((item) => item.toString()).toList()
          : const [],
      dialogue: rawDialogue is List
          ? rawDialogue
                .whereType<Map<String, dynamic>>()
                .map(DailyLifeDialogueLine.fromMap)
                .toList()
          : const [],
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    id,
    situationId,
    phraseEn,
    meaningEs,
    whenToUseEs,
    tone,
    exampleEn,
    pronunciation,
    variants,
    dialogue,
    sortOrder,
  ];
}

class DailyLifeDialogueLine extends Equatable {
  const DailyLifeDialogueLine({required this.speaker, required this.text});

  final String speaker;
  final String text;

  factory DailyLifeDialogueLine.fromMap(Map<String, dynamic> map) {
    return DailyLifeDialogueLine(
      speaker: map['speaker']?.toString() ?? 'A',
      text: map['text']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [speaker, text];
}

class DailyLifePracticeQuestion extends Equatable {
  const DailyLifePracticeQuestion({
    required this.id,
    required this.situationId,
    required this.prompt,
    required this.options,
    required this.sortOrder,
    this.explanationEs,
  });

  final String id;
  final String situationId;
  final String prompt;
  final String? explanationEs;
  final List<DailyLifePracticeOption> options;
  final int sortOrder;

  DailyLifePracticeOption? get correctOption {
    for (final option in options) {
      if (option.isCorrect) return option;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    id,
    situationId,
    prompt,
    explanationEs,
    options,
    sortOrder,
  ];
}

class DailyLifePracticeOption extends Equatable {
  const DailyLifePracticeOption({
    required this.id,
    required this.questionId,
    required this.text,
    required this.isCorrect,
    required this.sortOrder,
  });

  final String id;
  final String questionId;
  final String text;
  final bool isCorrect;
  final int sortOrder;

  factory DailyLifePracticeOption.fromMap(Map<String, dynamic> map) {
    return DailyLifePracticeOption(
      id: map['id'] as String,
      questionId: map['question_id'] as String,
      text: map['text'] as String,
      isCorrect: map['is_correct'] as bool? ?? false,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, questionId, text, isCorrect, sortOrder];
}

class DailyLifeSituationBundle extends Equatable {
  const DailyLifeSituationBundle({
    required this.situation,
    required this.expressions,
    required this.technicalQuestions,
    required this.questions,
  });

  final DailyLifeSituation situation;
  final List<DailyLifeExpression> expressions;
  final List<TechnicalInterviewQuestion> technicalQuestions;
  final List<DailyLifePracticeQuestion> questions;

  @override
  List<Object?> get props => [
    situation,
    expressions,
    technicalQuestions,
    questions,
  ];
}
