import 'package:equatable/equatable.dart';

enum ChatRole { user, assistant }

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final ChatRole role;
  final String content;
  final DateTime createdAt;

  bool get isUser => role == ChatRole.user;
  bool get isAssistant => role == ChatRole.assistant;

  Map<String, String> toApiMap() => {
    'role': role == ChatRole.user ? 'user' : 'assistant',
    'content': content,
  };

  @override
  List<Object?> get props => [role, content, createdAt];
}
