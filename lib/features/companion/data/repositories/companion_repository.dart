import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/chat_message.dart';

class CompanionContext {
  const CompanionContext({this.level, this.ageGroup, this.lesson, this.vocab});

  final String? level;
  final String? ageGroup;
  final String? lesson;
  final List<String>? vocab;

  Map<String, dynamic> toMap() => {
    if (level != null) 'level': level,
    if (ageGroup != null) 'ageGroup': ageGroup,
    if (lesson != null) 'lessonContext': lesson,
    if (vocab != null && vocab!.isNotEmpty) 'vocabularyFocus': vocab,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CompanionContext &&
        other.level == level &&
        other.ageGroup == ageGroup &&
        other.lesson == lesson &&
        _sameStringList(other.vocab, vocab);
  }

  @override
  int get hashCode => Object.hash(
    level,
    ageGroup,
    lesson,
    Object.hashAll(vocab ?? const <String>[]),
  );
}

bool _sameStringList(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class CompanionRepository {
  CompanionRepository(this._client);
  final SupabaseClient _client;

  Future<String> sendMessage({
    required List<ChatMessage> history,
    CompanionContext context = const CompanionContext(),
  }) async {
    final body = {
      'messages': history.map((m) => m.toApiMap()).toList(),
      ...context.toMap(),
    };
    try {
      final res = await _client.functions.invoke('companion-chat', body: body);
      if (res.status >= 400) {
        throw ServerFailure(_friendlyError(res.status, res.data));
      }
      final data = res.data;
      if (data is Map && data['reply'] is String) {
        final reply = (data['reply'] as String).trim();
        if (reply.isEmpty) {
          throw const ServerFailure(
            'El tutor no respondió. Inténtalo de nuevo.',
          );
        }
        return reply;
      }
      throw const ServerFailure('Respuesta inválida del companion-chat.');
    } on FunctionException catch (e) {
      throw ServerFailure(_friendlyError(e.status, e.details), cause: e);
    } catch (e) {
      if (e is Failure) rethrow;
      throw UnknownFailure('Error inesperado en companion-chat', e);
    }
  }

  String _friendlyError(int status, dynamic details) {
    final detailStr = details?.toString() ?? '';
    if (status == 404) {
      return 'La función companion-chat no está desplegada. '
          'Corre "supabase functions deploy companion-chat".';
    }
    if (status == 401 || status == 403) {
      return 'Necesitas iniciar sesión para hablar con Chepia.';
    }
    if (detailStr.contains('missing_openai_api_key')) {
      return 'Falta configurar OPENAI_API_KEY como secret en Supabase. '
          'Ejecuta "supabase secrets set OPENAI_API_KEY=tu_key".';
    }
    if (status >= 500) {
      return 'El tutor tuvo un error interno ($status). Intenta en unos segundos.';
    }
    return 'No pudimos contactar al tutor ($status). $detailStr';
  }
}

final companionRepositoryProvider = Provider<CompanionRepository>((ref) {
  return CompanionRepository(Supabase.instance.client);
});
