import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_state_views.dart';
import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../../lesson/presentation/widgets/content_loading_view.dart';

class ContentAudit {
  const ContentAudit({
    required this.levels,
    required this.books,
    required this.lessons,
    required this.pdfAssets,
    required this.audioAssets,
    required this.studyGuides,
    required this.quizzes,
    required this.vocabularyTerms,
  });

  final int levels;
  final int books;
  final int lessons;
  final int pdfAssets;
  final int audioAssets;
  final int studyGuides;
  final int quizzes;
  final int vocabularyTerms;

  bool get hasCoreCatalog => levels > 0 && books > 0 && lessons > 0;
  bool get hasStudyAssets => pdfAssets > 0 && audioAssets > 0;
  bool get hasPractice => quizzes > 0 && vocabularyTerms > 0;
}

final contentAuditProvider = FutureProvider<ContentAudit>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  Future<int> count(String label, Future<dynamic> Function() run) async {
    try {
      final res = await run();
      return res is List ? res.length : 0;
    } catch (_) {
      return 0;
    }
  }

  final results = await Future.wait([
    count('levels', () => client.from('levels').select('id')),
    count('books', () => client.from('books').select('id')),
    count('lessons', () => client.from('lessons').select('id')),
    count(
      'pdfAssets',
      () => client.from('assets').select('id').eq('kind', 'pdf'),
    ),
    count(
      'audioAssets',
      () => client.from('assets').select('id').eq('kind', 'audio'),
    ),
    count(
      'studyGuides',
      () => client.from('assets').select('id').eq('kind', 'study_guide'),
    ),
    count('quizzes', () => client.from('quizzes').select('id')),
    count(
      'lessonVocabulary',
      () => client.from('lesson_vocabulary').select('id'),
    ),
  ]);

  return ContentAudit(
    levels: results[0],
    books: results[1],
    lessons: results[2],
    pdfAssets: results[3],
    audioAssets: results[4],
    studyGuides: results[5],
    quizzes: results[6],
    vocabularyTerms: results[7],
  );
});

class AdminContentScreen extends ConsumerWidget {
  const AdminContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(contentAuditProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Panel de contenido')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(contentAuditProvider),
        child: auditAsync.when(
          loading: () =>
              const ContentLoadingView(status: 'Revisando contenido...'),
          error: (_, _) => AppErrorView(
            title: 'No se pudo auditar el contenido',
            message:
                'Revisa la sesión, las políticas RLS o las migraciones de Supabase.',
            onRetry: () => ref.invalidate(contentAuditProvider),
          ),
          data: (audit) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _AuditHero(audit: audit),
              const SizedBox(height: 16),
              _AuditGrid(audit: audit),
              const SizedBox(height: 16),
              const _AdminChecklist(),
              const SizedBox(height: 16),
              const _ScriptCommands(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditHero extends StatelessWidget {
  const _AuditHero({required this.audit});

  final ContentAudit audit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ready = audit.hasCoreCatalog && audit.hasStudyAssets;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ready
              ? colors.secondary.withValues(alpha: 0.28)
              : colors.error.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.verified_outlined : Icons.warning_amber_rounded,
            color: ready ? colors.secondary : colors.error,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? 'Contenido base listo' : 'Falta contenido base',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ready
                      ? 'La app ya tiene catálogo y assets principales.'
                      : 'Carga niveles, libros, lecciones, PDFs y audios antes de publicar.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditGrid extends StatelessWidget {
  const _AuditGrid({required this.audit});

  final ContentAudit audit;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Niveles', audit.levels, Icons.school_outlined),
      ('Libros', audit.books, Icons.library_books_outlined),
      ('Lecciones', audit.lessons, Icons.list_alt_outlined),
      ('PDFs', audit.pdfAssets, Icons.picture_as_pdf_outlined),
      ('Audios', audit.audioAssets, Icons.headphones_outlined),
      ('Study guides', audit.studyGuides, Icons.assignment_outlined),
      ('Quizzes', audit.quizzes, Icons.quiz_outlined),
      ('Vocabulario', audit.vocabularyTerms, Icons.style_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 760 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 4 ? 1.55 : 1.32,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _AuditTile(title: item.$1, count: item.$2, icon: item.$3);
          },
        );
      },
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({
    required this.title,
    required this.count,
    required this.icon,
  });

  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const Spacer(),
          Text(
            '$count',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AdminChecklist extends StatelessWidget {
  const _AdminChecklist();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _ChecklistRow(
              title: '1. Procesar PDFs y audios',
              body: 'Convierte WMA a MP3 y genera imágenes por página.',
            ),
            _ChecklistRow(
              title: '2. Subir contenido',
              body: 'Registra libros, lecciones y assets en Supabase.',
            ),
            _ChecklistRow(
              title: '3. Generar práctica',
              body: 'Crea quizzes y vocabulario por lección.',
            ),
            _ChecklistRow(
              title: '4. Validar en la app',
              body: 'Abre un libro, descarga offline, responde quiz y repasa.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScriptCommands extends StatelessWidget {
  const _ScriptCommands();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comandos locales',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const _CommandLine('bash scripts/convert-audio.sh'),
            const _CommandLine('bash scripts/convert-pdf-to-images.sh'),
            const _CommandLine(
              'cd scripts/quiz_generator && npm run upload-content',
            ),
            const _CommandLine('node register-content.mjs'),
            const _CommandLine('npm run generate'),
            const _CommandLine('node generate-vocabulary.mjs'),
          ],
        ),
      ),
    );
  }
}

class _CommandLine extends StatelessWidget {
  const _CommandLine(this.command);

  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        command,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: colors.onSurface,
        ),
      ),
    );
  }
}
