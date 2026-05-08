import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/services/speech_service.dart';
import '../../../../shared/services/tts_service.dart';
import '../../../onboarding/presentation/controllers/onboarding_providers.dart';
import '../../data/repositories/companion_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../controllers/companion_providers.dart';

class CompanionScreen extends ConsumerStatefulWidget {
  const CompanionScreen({super.key});

  @override
  ConsumerState<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends ConsumerState<CompanionScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _listening = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  CompanionContext _buildContext() {
    final onboarding = ref.read(onboardingStateProvider).valueOrNull;
    return CompanionContext(level: onboarding?.selectedLevelCode);
  }

  Future<void> _send([String? override]) async {
    final ctx = _buildContext();
    final text = (override ?? _input.text).trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref.read(companionControllerProvider(ctx).notifier).send(text);
    await Future.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await ref.read(speechServiceProvider).stop();
      setState(() => _listening = false);
      return;
    }
    final speech = ref.read(speechServiceProvider);
    final ok = await speech.ensureInitialized();
    if (!ok) return;
    setState(() => _listening = true);
    String latest = '';
    await for (final r in speech.listen()) {
      latest = r.transcript;
      if (mounted) _input.text = latest;
      if (r.finalResult) break;
    }
    if (!mounted) return;
    setState(() => _listening = false);
    if (latest.isNotEmpty) await _send(latest);
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _buildContext();
    final state = ref.watch(companionControllerProvider(ctx));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat con Chepia'),
        actions: [
          IconButton(
            tooltip: 'Reiniciar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(companionControllerProvider(ctx)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: state.messages.length + (state.isSending ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= state.messages.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: _TypingBubble(),
                  );
                }
                final msg = state.messages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _Bubble(message: msg),
                );
              },
            ),
          ),
          if (state.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              color: colors.errorContainer,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: colors.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(companionControllerProvider(ctx).notifier)
                        .clearError(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filledTonal(
                    tooltip: _listening ? 'Detener' : 'Hablar',
                    onPressed: state.isSending ? null : _toggleListen,
                    icon: Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !state.isSending,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Escribe en inglés (o español)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar',
                    onPressed: state.isSending ? null : () => _send(),
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final bg = isUser ? colors.primaryContainer : colors.surfaceContainerHigh;
    final fg = isUser ? colors.onPrimaryContainer : colors.onSurface;
    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isUser)
          IconButton(
            tooltip: 'Escuchar',
            onPressed: () => ref.read(ttsServiceProvider).speak(message.content),
            icon: Icon(Icons.volume_up_rounded, color: colors.primary),
          ),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              message.content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Chepia escribe...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
