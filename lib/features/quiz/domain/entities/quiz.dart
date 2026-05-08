import 'package:equatable/equatable.dart';

enum QuestionKind { multipleChoice, trueFalse, fillBlank, listening }

QuestionKind parseQuestionKind(String raw) {
  switch (raw) {
    case 'multiple_choice':
      return QuestionKind.multipleChoice;
    case 'true_false':
      return QuestionKind.trueFalse;
    case 'fill_blank':
      return QuestionKind.fillBlank;
    case 'listening':
      return QuestionKind.listening;
    default:
      return QuestionKind.multipleChoice;
  }
}

class QuizOption extends Equatable {
  const QuizOption({
    required this.id,
    required this.text,
    required this.isCorrect,
    required this.sortOrder,
  });

  final String id;
  final String text;
  final bool isCorrect;
  final int sortOrder;

  factory QuizOption.fromMap(Map<String, dynamic> m) => QuizOption(
    id: m['id'] as String,
    text: m['text'] as String,
    isCorrect: (m['is_correct'] as bool?) ?? false,
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [id, text, isCorrect, sortOrder];
}

class QuizQuestion extends Equatable {
  const QuizQuestion({
    required this.id,
    required this.prompt,
    required this.kind,
    required this.options,
    this.explanation,
    this.audioAssetId,
    this.sortOrder = 0,
  });

  final String id;
  final String prompt;
  final QuestionKind kind;
  final List<QuizOption> options;
  final String? explanation;
  final String? audioAssetId;
  final int sortOrder;

  QuizOption? get correctOption {
    for (final o in options) {
      if (o.isCorrect) return o;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    id,
    prompt,
    kind,
    options,
    explanation,
    sortOrder,
  ];
}

class Quiz extends Equatable {
  const Quiz({
    required this.id,
    required this.lessonId,
    required this.kind,
    required this.passingScore,
    required this.questions,
  });

  final String id;
  final String lessonId;
  final String kind; // 'lesson' | 'review_5'
  final int passingScore;
  final List<QuizQuestion> questions;

  @override
  List<Object?> get props => [id, lessonId, kind, passingScore, questions];
}

class QuizAttemptResult extends Equatable {
  const QuizAttemptResult({
    required this.attemptId,
    required this.score,
    required this.total,
    required this.passed,
  });

  final String attemptId;
  final int score;
  final int total;
  final bool passed;

  double get percentage => total == 0 ? 0 : (score / total) * 100;

  @override
  List<Object?> get props => [attemptId, score, total, passed];
}
