import 'package:equatable/equatable.dart';

class ReadingProgress extends Equatable {
  const ReadingProgress({
    required this.lessonId,
    required this.lastPage,
    required this.isCompleted,
    this.updatedAt,
  });

  final String lessonId;
  final int lastPage;
  final bool isCompleted;
  final DateTime? updatedAt;

  factory ReadingProgress.fromMap(Map<String, dynamic> m) => ReadingProgress(
        lessonId: m['lesson_id'] as String,
        lastPage: (m['last_page'] as num?)?.toInt() ?? 1,
        isCompleted: (m['is_completed'] as bool?) ?? false,
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [lessonId, lastPage, isCompleted, updatedAt];
}

class AudioProgress extends Equatable {
  const AudioProgress({
    required this.lessonId,
    required this.lastPositionSec,
    required this.isCompleted,
    this.updatedAt,
  });

  final String lessonId;
  final int lastPositionSec;
  final bool isCompleted;
  final DateTime? updatedAt;

  factory AudioProgress.fromMap(Map<String, dynamic> m) => AudioProgress(
        lessonId: m['lesson_id'] as String,
        lastPositionSec: (m['last_position_sec'] as num?)?.toInt() ?? 0,
        isCompleted: (m['is_completed'] as bool?) ?? false,
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [lessonId, lastPositionSec, isCompleted, updatedAt];
}
