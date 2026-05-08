import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../lesson/presentation/widgets/content_loading_view.dart';
import '../../../../shared/widgets/app_state_views.dart';
import '../../domain/entities/quiz.dart';
import '../controllers/quiz_providers.dart';

class QuizScreen extends ConsumerWidget {
  const QuizScreen({
    super.key,
    required this.bookSlug,
    required this.lessonNumber,
  });
  final String bookSlug;
  final int lessonNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizAsync = ref.watch(
      lessonQuizProvider((bookSlug: bookSlug, lessonNumber: lessonNumber)),
    );

    return Scaffold(
      appBar: AppBar(title: Text('Quiz · Lesson $lessonNumber')),
      body: quizAsync.when(
        loading: () => const ContentLoadingView(status: 'Preparando quiz...'),
        error: (e, _) => AppErrorView(
          title: 'No se pudo cargar el quiz',
          message:
              'Revisa conexión, permisos de Supabase o que la lección exista. Detalle: $e',
          onRetry: () => ref.invalidate(
            lessonQuizProvider((
              bookSlug: bookSlug,
              lessonNumber: lessonNumber,
            )),
          ),
        ),
        data: (quiz) {
          if (quiz == null || quiz.questions.isEmpty) {
            return const AppEmptyView(
              title: 'Sin quiz todavía',
              message:
                  'Genera quizzes desde scripts/quiz_generator/generate.mjs o revisa el panel de contenido.',
              icon: Icons.quiz_outlined,
            );
          }
          return _QuizRunner(quiz: quiz);
        },
      ),
    );
  }
}

class _QuizRunner extends ConsumerStatefulWidget {
  const _QuizRunner({required this.quiz});
  final Quiz quiz;

  @override
  ConsumerState<_QuizRunner> createState() => _QuizRunnerState();
}

class _QuizRunnerState extends ConsumerState<_QuizRunner> {
  String? _attemptId;
  int _index = 0;
  int _correctCount = 0;
  String? _selectedOptionId;
  bool _showFeedback = false;
  bool _isStartingAttempt = true;
  bool _isBusy = false;
  String? _attemptError;
  String? _finishError;
  QuizAttemptResult? _result;
  bool _reviewMode = false;
  List<QuizQuestion> _reviewQuestions = const [];
  final _missedQuestions = <QuizQuestion>[];

  List<QuizQuestion> get _questions =>
      _reviewMode ? _reviewQuestions : widget.quiz.questions;

  @override
  void initState() {
    super.initState();
    _startAttempt();
  }

  Future<void> _startAttempt() async {
    setState(() {
      _attemptId = null;
      _index = 0;
      _correctCount = 0;
      _selectedOptionId = null;
      _showFeedback = false;
      _result = null;
      _reviewMode = false;
      _reviewQuestions = const [];
      _missedQuestions.clear();
      _isBusy = false;
      _attemptError = null;
      _finishError = null;
      _isStartingAttempt = true;
    });
    try {
      final id = await ref
          .read(quizRepositoryProvider)
          .startAttempt(quizId: widget.quiz.id);
      if (!mounted) return;
      setState(() {
        _attemptId = id;
        _isStartingAttempt = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _attemptError = 'No se pudo iniciar el quiz. Intenta de nuevo.';
        _isStartingAttempt = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedOptionId == null || _showFeedback || _isBusy) return;
    final question = _questions[_index];
    final option = question.options.firstWhere(
      (o) => o.id == _selectedOptionId,
    );
    setState(() {
      _isBusy = true;
      _showFeedback = true;
      if (option.isCorrect) {
        _correctCount++;
      } else if (!_missedQuestions.any((q) => q.id == question.id)) {
        _missedQuestions.add(question);
      }
    });

    final attemptId = _attemptId;
    if (attemptId != null) {
      await ref
          .read(quizRepositoryProvider)
          .recordAnswer(
            attemptId: attemptId,
            questionId: question.id,
            optionId: option.id,
            isCorrect: option.isCorrect,
          );
    }
    if (!mounted) return;
    setState(() => _isBusy = false);
  }

  Future<void> _next() async {
    if (_isBusy) return;
    final questions = _questions;
    if (_index < questions.length - 1) {
      setState(() {
        _index++;
        _selectedOptionId = null;
        _showFeedback = false;
        _finishError = null;
      });
    } else {
      if (_reviewMode) {
        setState(() {
          _result = QuizAttemptResult(
            attemptId: 'review',
            score: _correctCount,
            total: questions.length,
            passed: _correctCount == questions.length,
          );
        });
        return;
      }

      // Finalizar
      final attemptId = _attemptId;
      if (attemptId == null) {
        setState(() {
          _attemptError = 'El intento no quedó listo. Intenta de nuevo.';
        });
        return;
      }
      setState(() {
        _isBusy = true;
        _finishError = null;
      });
      try {
        final result = await ref
            .read(quizRepositoryProvider)
            .finishAttempt(
              attemptId: attemptId,
              score: _correctCount,
              total: questions.length,
              passingScore: widget.quiz.passingScore,
            );
        if (!mounted) return;
        setState(() => _result = result);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _finishError = 'No se pudo guardar el resultado. Intenta de nuevo.';
        });
      } finally {
        if (mounted && _result == null) {
          setState(() => _isBusy = false);
        }
      }
    }
  }

  void _reviewMissedQuestions() {
    if (_missedQuestions.isEmpty) return;
    setState(() {
      _reviewMode = true;
      _reviewQuestions = List.unmodifiable(_missedQuestions);
      _missedQuestions.clear();
      _attemptId = null;
      _index = 0;
      _correctCount = 0;
      _selectedOptionId = null;
      _showFeedback = false;
      _result = null;
      _isBusy = false;
      _attemptError = null;
      _finishError = null;
      _isStartingAttempt = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) {
      return _ResultView(
        result: result,
        missedQuestions: List.unmodifiable(_missedQuestions),
        isReviewMode: _reviewMode,
        onRetry: _startAttempt,
        onReviewMissed: _missedQuestions.isEmpty
            ? null
            : _reviewMissedQuestions,
      );
    }
    if (_attemptError != null) {
      return _AttemptErrorView(message: _attemptError!, onRetry: _startAttempt);
    }
    if (_isStartingAttempt) {
      return const ContentLoadingView(status: 'Iniciando intento...');
    }

    final question = _questions[_index];
    final total = _questions.length;
    final selected = _selectedOptionId;
    final selectedOption = selected == null
        ? null
        : question.options.firstWhere((o) => o.id == selected);

    return SafeArea(
      child: Column(
        children: [
          LinearProgressIndicator(
            value: total == 0 ? 0 : (_index + 1) / total,
            minHeight: 4,
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  '${_index + 1} / $total',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    _reviewMode ? 'Repaso' : _kindLabel(question.kind),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    question.prompt,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...question.options.map((opt) {
                    final isSelected = opt.id == _selectedOptionId;
                    Color? bg;
                    Color? border;
                    if (_showFeedback) {
                      if (opt.isCorrect) {
                        bg = Colors.green.withValues(alpha: 0.1);
                        border = Colors.green;
                      } else if (isSelected) {
                        bg = Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.1);
                        border = Theme.of(context).colorScheme.error;
                      }
                    } else if (isSelected) {
                      bg = Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08);
                      border = Theme.of(context).colorScheme.primary;
                    }
                    bg ??= Theme.of(context).colorScheme.surfaceContainerHigh;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: _showFeedback || _isBusy
                            ? null
                            : () => setState(() => _selectedOptionId = opt.id),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: border ?? Theme.of(context).dividerColor,
                              width: border != null ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _showFeedback
                                    ? (opt.isCorrect
                                          ? Icons.check_circle
                                          : (isSelected
                                                ? Icons.cancel
                                                : Icons.radio_button_unchecked))
                                    : (isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked),
                                color: border,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  opt.text,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  if (_showFeedback) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (selectedOption?.isCorrect ?? false)
                                ? '¡Correcto!'
                                : 'Incorrecto',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (question.explanation != null) ...[
                            const SizedBox(height: 6),
                            Text(question.explanation!),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_finishError != null) ...[
                    Text(
                      _finishError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: _selectedOptionId == null || _isBusy
                        ? null
                        : (_showFeedback ? _next : _submit),
                    child: _isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _showFeedback
                                ? (_index < total - 1
                                      ? 'Siguiente'
                                      : 'Ver resultado')
                                : 'Comprobar',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(QuestionKind k) {
    switch (k) {
      case QuestionKind.multipleChoice:
        return 'Comprehension';
      case QuestionKind.trueFalse:
        return 'True/False';
      case QuestionKind.fillBlank:
        return 'Fill blank';
      case QuestionKind.listening:
        return 'Listening';
    }
  }
}

class _AttemptErrorView extends StatelessWidget {
  const _AttemptErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.result,
    required this.missedQuestions,
    required this.isReviewMode,
    required this.onRetry,
    this.onReviewMissed,
  });

  final QuizAttemptResult result;
  final List<QuizQuestion> missedQuestions;
  final bool isReviewMode;
  final VoidCallback onRetry;
  final VoidCallback? onReviewMissed;

  @override
  Widget build(BuildContext context) {
    final color = result.passed
        ? Colors.green
        : Theme.of(context).colorScheme.error;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              result.passed ? Icons.emoji_events : Icons.replay,
              size: 96,
              color: color,
            ),
            const SizedBox(height: 16),
            Text(
              isReviewMode
                  ? (result.passed ? 'Repaso completo' : 'Sigue repasando')
                  : (result.passed ? '¡Aprobaste!' : 'Inténtalo de nuevo'),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${result.score} / ${result.total} (${result.percentage.toStringAsFixed(0)}%)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (missedQuestions.isNotEmpty) ...[
              const SizedBox(height: 24),
              _MissedQuestionsPanel(questions: missedQuestions),
            ],
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                if (onReviewMissed != null)
                  FilledButton.icon(
                    onPressed: onReviewMissed,
                    icon: const Icon(Icons.psychology_alt_outlined),
                    label: const Text('Repasar falladas'),
                  ),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar completo'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Volver al libro'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MissedQuestionsPanel extends StatelessWidget {
  const _MissedQuestionsPanel({required this.questions});

  final List<QuizQuestion> questions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Errores para repasar',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final question in questions) ...[
              Text(
                question.prompt,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (question.correctOption != null) ...[
                const SizedBox(height: 4),
                Text('Respuesta: ${question.correctOption!.text}'),
              ],
              if (question.explanation != null) ...[
                const SizedBox(height: 4),
                Text(
                  question.explanation!,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
              if (question != questions.last)
                Divider(height: 22, color: colors.outlineVariant),
            ],
          ],
        ),
      ),
    );
  }
}
