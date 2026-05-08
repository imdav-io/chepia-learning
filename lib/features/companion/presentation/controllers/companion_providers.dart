import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../data/repositories/companion_repository.dart';
import '../../domain/entities/chat_message.dart';

class CompanionState {
  const CompanionState({
    this.messages = const [],
    this.isSending = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool isSending;
  final String? error;

  CompanionState copyWith({
    List<ChatMessage>? messages,
    bool? isSending,
    String? error,
    bool clearError = false,
  }) {
    return CompanionState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CompanionController extends StateNotifier<CompanionState> {
  CompanionController(this._repo, this._context)
    : super(
        CompanionState(
          messages: [
            ChatMessage(
              role: ChatRole.assistant,
              content: _greetingFor(_context),
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );

  final CompanionRepository _repo;
  final CompanionContext _context;

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;
    final userMsg = ChatMessage(
      role: ChatRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isSending: true,
      clearError: true,
    );
    try {
      final reply = await _repo.sendMessage(
        history: state.messages,
        context: _context,
      );
      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(
            role: ChatRole.assistant,
            content: reply.trim(),
            createdAt: DateTime.now(),
          ),
        ],
        isSending: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSending: false,
        error: e is Failure ? e.message : 'No pudimos contactar a Chepia.',
      );
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

String _greetingFor(CompanionContext ctx) {
  final audience = ctx.ageGroup;
  if (audience == 'kid') {
    return "Hi! I'm Chepia. Let's play with English. What did you do today?";
  }
  if (audience == 'teen') {
    return "Hey! Ready for a quick English chat? Tell me what you're up to.";
  }
  return "Hi! I'm your English coach. What would you like to practice today?";
}

final companionControllerProvider = StateNotifierProvider.autoDispose
    .family<CompanionController, CompanionState, CompanionContext>((ref, ctx) {
      final repo = ref.watch(companionRepositoryProvider);
      return CompanionController(repo, ctx);
    });
