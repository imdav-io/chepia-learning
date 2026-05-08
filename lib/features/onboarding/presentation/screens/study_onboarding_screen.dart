import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/level_style.dart';
import '../../../../shared/widgets/app_state_views.dart';
import '../../../catalog/domain/entities/level.dart';
import '../../../catalog/presentation/controllers/catalog_providers.dart';
import '../../../lesson/presentation/widgets/content_loading_view.dart';
import '../controllers/onboarding_providers.dart';

class StudyOnboardingScreen extends ConsumerStatefulWidget {
  const StudyOnboardingScreen({super.key});

  @override
  ConsumerState<StudyOnboardingScreen> createState() =>
      _StudyOnboardingScreenState();
}

class _StudyOnboardingScreenState extends ConsumerState<StudyOnboardingScreen> {
  String? _selectedLevelCode;
  var _isStarting = false;
  String? _errorMessage;

  Future<void> _start() async {
    final code = _selectedLevelCode;
    if (code == null || _isStarting) return;

    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(onboardingPreferencesProvider)
          .complete(selectedLevelCode: code);
      ref.invalidate(onboardingStateProvider);

      final books = await ref.read(booksByLevelProvider(code).future);
      if (!mounted) return;
      if (books.isEmpty) {
        context.go('/catalog/levels/$code');
      } else {
        context.go('/book/${books.first.slug}');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No se pudo preparar tu primera lección. Intenta de nuevo.';
        _isStarting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final levelsAsync = ref.watch(levelsProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: levelsAsync.when(
          loading: () => const ContentLoadingView(
            status: 'Preparando tu ruta de estudio...',
          ),
          error: (e, _) => AppErrorView(
            title: 'No pudimos cargar los niveles',
            message:
                'Revisa tu conexión o la configuración de Supabase. Después intenta otra vez.',
            onRetry: () => ref.invalidate(levelsProvider),
          ),
          data: (levels) {
            if (levels.isEmpty) {
              return const AppEmptyView(
                title: 'Aún no hay niveles',
                message:
                    'Carga niveles y libros en Supabase para iniciar la experiencia de estudio.',
                icon: Icons.school_outlined,
              );
            }
            _selectedLevelCode ??= levels.first.code;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tu plan empieza hoy',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Elige un nivel. La app te llevará a leer, escuchar, repasar vocabulario y cerrar con quiz sin que tengas que adivinar qué sigue.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const _StudyPathPreview(),
                const SizedBox(height: 22),
                Text(
                  'Nivel inicial',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...levels.map(
                  (level) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _LevelChoice(
                      level: level,
                      isSelected: _selectedLevelCode == level.code,
                      onTap: () =>
                          setState(() => _selectedLevelCode = level.code),
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(_errorMessage!, style: TextStyle(color: colors.error)),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _selectedLevelCode == null || _isStarting
                      ? null
                      : _start,
                  icon: _isStarting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('Empezar primera lección'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StudyPathPreview extends StatelessWidget {
  const _StudyPathPreview();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 620;
        final items = const [
          _PathStep(
            icon: Icons.menu_book_outlined,
            title: 'Lee',
            body: 'Avanza en la lección activa.',
          ),
          _PathStep(
            icon: Icons.headphones_outlined,
            title: 'Escucha',
            body: 'Completa el audio sin perder tu avance.',
          ),
          _PathStep(
            icon: Icons.style_outlined,
            title: 'Repasa',
            body: 'Vocabulario justo cuando toca.',
          ),
          _PathStep(
            icon: Icons.quiz_outlined,
            title: 'Prueba',
            body: 'Cierra con quiz y feedback.',
          ),
        ];

        if (isNarrow) {
          return Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: item,
                ),
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              Expanded(child: items[i]),
              if (i < items.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _PathStep extends StatelessWidget {
  const _PathStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LevelChoice extends StatelessWidget {
  const _LevelChoice({
    required this.level,
    required this.isSelected,
    required this.onTap,
  });

  final Level level;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = LevelPalette.forStyle(levelStyleForCode(level.code));
    return Material(
      color: isSelected
          ? palette.primary.withValues(alpha: 0.14)
          : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected ? palette.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _levelName(level.code),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _levelDescription(level.code),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _PaletteDots(palette: palette),
            ],
          ),
        ),
      ),
    );
  }

  String _levelName(String code) {
    switch (code) {
      case 'beginner':
        return 'Beginner';
      case 'intermediate':
        return 'Intermediate';
      case 'advanced':
        return 'Advanced';
      default:
        return code;
    }
  }

  String _levelDescription(String code) {
    switch (code) {
      case 'beginner':
        return 'Tema vivo: ámbar, rosa y lila para empezar.';
      case 'intermediate':
        return 'Tema balanceado: cian y verde para mantener el ritmo.';
      case 'advanced':
        return 'Tema sobrio: azules apagados para enfocarte.';
      default:
        return code;
    }
  }
}

class _PaletteDots extends StatelessWidget {
  const _PaletteDots({required this.palette});

  final LevelPalette palette;

  @override
  Widget build(BuildContext context) {
    final dots = [palette.primary, palette.secondary, palette.tertiary];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < dots.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dots[i],
              boxShadow: [
                BoxShadow(
                  color: dots[i].withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
