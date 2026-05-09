import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/app_state_views.dart';
import '../../../lesson/presentation/widgets/content_loading_view.dart';
import '../../domain/entities/daily_life_situation.dart';
import '../controllers/daily_life_providers.dart';

class SituationDetailScreen extends ConsumerWidget {
  const SituationDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundleAsync = ref.watch(dailyLifeSituationProvider(slug));

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: ContentLoadingView(status: 'Preparando práctica...'),
      ),
      error: (error, _) => Scaffold(
        body: AppErrorView(
          title: 'No se pudo cargar esta situación',
          message: error.toString(),
          onRetry: () => ref.invalidate(dailyLifeSituationProvider(slug)),
        ),
      ),
      data: (bundle) {
        if (bundle == null) {
          return const Scaffold(
            body: AppEmptyView(
              title: 'Situación no encontrada',
              message: 'Regresa a Situaciones y elige otra práctica.',
              icon: Icons.search_off_outlined,
            ),
          );
        }
        return _SituationDetail(bundle: bundle);
      },
    );
  }
}

class _SituationDetail extends StatefulWidget {
  const _SituationDetail({required this.bundle});

  final DailyLifeSituationBundle bundle;

  @override
  State<_SituationDetail> createState() => _SituationDetailState();
}

class _SituationDetailState extends State<_SituationDetail> {
  var _selectedIndex = 0;

  bool get _isTechnicalInterview {
    final bundle = widget.bundle;
    return bundle.situation.isTechnicalInterview ||
        bundle.technicalQuestions.isNotEmpty;
  }

  int get _total {
    final bundle = widget.bundle;
    return _isTechnicalInterview
        ? bundle.technicalQuestions.length
        : bundle.expressions.length;
  }

  int get _safeIndex {
    if (_total == 0) return 0;
    return _selectedIndex.clamp(0, _total - 1).toInt();
  }

  void _previous() {
    if (_safeIndex == 0) return;
    setState(() => _selectedIndex = _safeIndex - 1);
  }

  void _next() {
    if (_safeIndex >= _total - 1) return;
    setState(() => _selectedIndex = _safeIndex + 1);
  }

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final selectedIndex = _safeIndex;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(bundle.situation.titleEs),
          actions: [
            IconButton(
              tooltip: 'Hablar con Chepia',
              onPressed: () => context.push('/companion'),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.style_outlined), text: 'Estudiar'),
              Tab(icon: Icon(Icons.quiz_outlined), text: 'Quiz'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _StudyPane(
              bundle: bundle,
              isTechnicalInterview: _isTechnicalInterview,
              selectedIndex: selectedIndex,
              total: _total,
              onPrevious: selectedIndex == 0 ? null : _previous,
              onNext: selectedIndex >= _total - 1 ? null : _next,
            ),
            _QuizPane(questions: bundle.questions),
          ],
        ),
      ),
    );
  }
}

class _StudyPane extends StatelessWidget {
  const _StudyPane({
    required this.bundle,
    required this.isTechnicalInterview,
    required this.selectedIndex,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final DailyLifeSituationBundle bundle;
  final bool isTechnicalInterview;
  final int selectedIndex;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return const AppEmptyView(
        title: 'Sin contenido de estudio',
        message: 'Regenera esta situación para llenar sus tarjetas.',
        icon: Icons.style_outlined,
      );
    }

    final studyCard = isTechnicalInterview
        ? _TechnicalStudyCard(
            question: bundle.technicalQuestions[selectedIndex],
            current: selectedIndex + 1,
            total: total,
            onPrevious: onPrevious,
            onNext: onNext,
          )
        : _ExpressionStudyCard(
            expression: bundle.expressions[selectedIndex],
            current: selectedIndex + 1,
            total: total,
            onPrevious: onPrevious,
            onNext: onNext,
          );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 920;
          final header = _StudyHeader(bundle: bundle);
          if (isWide) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 340, child: header),
                  const SizedBox(width: 16),
                  Expanded(child: studyCard),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                header,
                const SizedBox(height: 12),
                Expanded(child: studyCard),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StudyHeader extends StatelessWidget {
  const _StudyHeader({required this.bundle});

  final DailyLifeSituationBundle bundle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isTechnicalInterview =
        bundle.situation.isTechnicalInterview ||
        bundle.technicalQuestions.isNotEmpty;
    final contentCount = isTechnicalInterview
        ? bundle.technicalQuestions.length
        : bundle.expressions.length;
    final contentLabel = isTechnicalInterview
        ? '$contentCount preguntas técnicas'
        : '$contentCount expresiones';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bundle.situation.titleEn,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: colors.primary,
            ),
          ),
          if (bundle.situation.descriptionEs?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              bundle.situation.descriptionEs!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: bundle.situation.levelBand),
              _Pill(label: contentLabel),
              _Pill(label: '${bundle.questions.length} quiz'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpressionStudyCard extends StatelessWidget {
  const _ExpressionStudyCard({
    required this.expression,
    required this.current,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final DailyLifeExpression expression;
  final int current;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return _StudyFrame(
      icon: Icons.record_voice_over_outlined,
      label: 'Flashcard $current/$total',
      pills: [_Pill(label: expression.tone)],
      onPrevious: onPrevious,
      onNext: onNext,
      children: [
        Text(
          expression.phraseEn,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        _EmphasisText(text: expression.meaningEs),
        if (expression.whenToUseEs?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          _InfoSection(title: 'Cuándo usarla', body: expression.whenToUseEs!),
        ],
        if (expression.exampleEn?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          _InfoSection(title: 'Ejemplo', body: expression.exampleEn!),
        ],
        if (expression.pronunciation?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          _InfoSection(title: 'Pronunciación', body: expression.pronunciation!),
        ],
        if (expression.variants.isNotEmpty) ...[
          const SizedBox(height: 16),
          _PillGroup(title: 'Variantes', items: expression.variants),
        ],
        if (expression.dialogue.isNotEmpty) ...[
          const SizedBox(height: 16),
          _DialogueBlock(lines: expression.dialogue),
        ],
      ],
    );
  }
}

class _TechnicalStudyCard extends StatelessWidget {
  const _TechnicalStudyCard({
    required this.question,
    required this.current,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final TechnicalInterviewQuestion question;
  final int current;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[_Pill(label: question.difficulty)];
    if (question.category?.isNotEmpty ?? false) {
      pills.add(_Pill(label: question.category!));
    }

    return _StudyFrame(
      icon: Icons.psychology_outlined,
      label: 'Pregunta técnica $current/$total',
      pills: pills,
      onPrevious: onPrevious,
      onNext: onNext,
      children: [
        Text(
          question.questionEn,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        _InfoSection(title: 'Respuesta técnica', body: question.answerEn),
        if (question.answerEs?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          _InfoSection(
            title: 'Explicación en español',
            body: question.answerEs!,
          ),
        ],
        if (question.keyPoints.isNotEmpty) ...[
          const SizedBox(height: 16),
          _BulletGroup(title: 'Puntos clave', items: question.keyPoints),
        ],
        if (question.sampleAnswerEn?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          _InfoSection(
            title: 'Respuesta modelo',
            body: question.sampleAnswerEn!,
            italic: true,
          ),
        ],
        if (question.followUpQuestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          _BulletGroup(title: 'Follow-ups', items: question.followUpQuestions),
        ],
        if (question.commonMistakes.isNotEmpty) ...[
          const SizedBox(height: 16),
          _BulletGroup(
            title: 'Errores comunes',
            items: question.commonMistakes,
          ),
        ],
        if (question.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          _PillGroup(title: 'Tags', items: question.tags),
        ],
      ],
    );
  }
}

class _StudyFrame extends StatelessWidget {
  const _StudyFrame({
    required this.icon,
    required this.label,
    required this.pills,
    required this.children,
    required this.onPrevious,
    required this.onNext,
  });

  final IconData icon;
  final String label;
  final List<Widget> pills;
  final List<Widget> children;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.22),
            colors.surfaceContainerHigh,
            colors.tertiary.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(icon, color: colors.primary),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              ...pills,
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuizPane extends StatelessWidget {
  const _QuizPane({required this.questions});

  final List<DailyLifePracticeQuestion> questions;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const AppEmptyView(
        title: 'Sin quiz',
        message: 'Regenera esta situación para crear preguntas de práctica.',
        icon: Icons.quiz_outlined,
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _PracticeQuiz(questions: questions),
      ),
    );
  }
}

class _PracticeQuiz extends StatefulWidget {
  const _PracticeQuiz({required this.questions});

  final List<DailyLifePracticeQuestion> questions;

  @override
  State<_PracticeQuiz> createState() => _PracticeQuizState();
}

class _PracticeQuizState extends State<_PracticeQuiz> {
  final _answers = <String, String>{};
  var _showResults = false;
  var _currentIndex = 0;

  int get _safeIndex {
    return _currentIndex.clamp(0, widget.questions.length - 1).toInt();
  }

  int get _score {
    var score = 0;
    for (final question in widget.questions) {
      final selected = _answers[question.id];
      final correct = question.correctOption?.id;
      if (selected != null && selected == correct) score++;
    }
    return score;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final question = widget.questions[_safeIndex];
    final selected = _answers[question.id];
    final correct = question.correctOption?.id;
    final answeredAll = _answers.length == widget.questions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Quiz rápido',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            if (_showResults)
              _Pill(label: '$_score/${widget.questions.length}'),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: (_safeIndex + 1) / widget.questions.length,
          minHeight: 8,
          borderRadius: BorderRadius.circular(99),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Pill(
                  label:
                      'Pregunta ${_safeIndex + 1}/${widget.questions.length}',
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question.prompt,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 14),
                          for (final option in question.options)
                            _PracticeOptionTile(
                              text: option.text,
                              selected: selected == option.id,
                              correct:
                                  _showResults &&
                                  option.id == question.correctOption?.id,
                              wrong:
                                  _showResults &&
                                  selected == option.id &&
                                  selected != correct,
                              enabled: !_showResults,
                              onTap: () => setState(() {
                                _answers[question.id] = option.id;
                              }),
                            ),
                          if (_showResults) ...[
                            const SizedBox(height: 12),
                            _InfoSection(
                              title: selected == correct
                                  ? 'Correcto'
                                  : 'Revisa esta idea',
                              body:
                                  question.explanationEs ??
                                  'Respuesta: ${question.correctOption?.text ?? ''}',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: _safeIndex == 0
                  ? null
                  : () => setState(() => _currentIndex = _safeIndex - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _safeIndex >= widget.questions.length - 1
                  ? null
                  : () => setState(() => _currentIndex = _safeIndex + 1),
              icon: const Icon(Icons.chevron_right),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() {
                _answers.clear();
                _showResults = false;
                _currentIndex = 0;
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Reiniciar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: answeredAll
                  ? () => setState(() => _showResults = true)
                  : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Revisar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PracticeOptionTile extends StatelessWidget {
  const _PracticeOptionTile({
    required this.text,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.enabled,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final bool correct;
  final bool wrong;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = correct
        ? colors.secondary
        : wrong
        ? colors.error
        : selected
        ? colors.primary
        : colors.outlineVariant;
    final backgroundColor = correct
        ? colors.secondary.withValues(alpha: 0.12)
        : wrong
        ? colors.error.withValues(alpha: 0.10)
        : selected
        ? colors.primary.withValues(alpha: 0.10)
        : colors.surfaceContainerHighest.withValues(alpha: 0.36);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? borderColor : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.body,
    this.italic = false,
  });

  final String title;
  final String body;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontStyle: italic ? FontStyle.italic : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EmphasisText extends StatelessWidget {
  const _EmphasisText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: colors.primary,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _BulletGroup extends StatelessWidget {
  const _BulletGroup({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('- ', style: TextStyle(color: colors.primary)),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PillGroup extends StatelessWidget {
  const _PillGroup({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final item in items) _Pill(label: item)],
        ),
      ],
    );
  }
}

class _DialogueBlock extends StatelessWidget {
  const _DialogueBlock({required this.lines});

  final List<DailyLifeDialogueLine> lines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mini diálogo',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${line.speaker}: ${line.text}'),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}
