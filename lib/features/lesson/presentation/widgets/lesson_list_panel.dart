import 'package:flutter/material.dart';

import '../../../catalog/presentation/controllers/catalog_providers.dart';

class LessonListPanel extends StatelessWidget {
  const LessonListPanel({
    super.key,
    required this.lessons,
    required this.selectedLessonId,
    required this.onLessonTap,
    required this.onQuizTap,
    this.title,
    this.progressByLessonId = const {},
  });

  final List<LessonWithAudio> lessons;
  final String? selectedLessonId;
  final ValueChanged<LessonWithAudio> onLessonTap;
  final ValueChanged<LessonWithAudio> onQuizTap;
  final String? title;

  /// Mapa lessonId -> completada (audio escuchado). Usado para mostrar check.
  final Map<String, bool> progressByLessonId;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Text(
              title ?? 'Lecciones',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: lessons.length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (_, i) {
                final l = lessons[i];
                final isSelected = l.lesson.id == selectedLessonId;
                final isCompleted = progressByLessonId[l.lesson.id] ?? false;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08),
                  leading: CircleAvatar(
                    backgroundColor: isCompleted
                        ? Theme.of(context).colorScheme.tertiary
                        : isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                    foregroundColor: (isSelected || isCompleted)
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                    child: isCompleted
                        ? const Icon(Icons.check, size: 18)
                        : Text('${l.lesson.number}'),
                  ),
                  title: Text(
                    l.lesson.title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: l.lesson.pdfStartPage == null
                      ? null
                      : Text('pp. ${l.lesson.pdfStartPage}–${l.lesson.pdfEndPage}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (l.hasAudio)
                        Icon(
                          Icons.headphones,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      IconButton(
                        icon: const Icon(Icons.quiz_outlined),
                        tooltip: 'Quiz',
                        onPressed: () => onQuizTap(l),
                      ),
                    ],
                  ),
                  onTap: () => onLessonTap(l),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
