/// Abstracción para cualquier proveedor de IA (Claude, OpenAI, etc.).
/// Mantenida desacoplada para que el MVP no haga inferencia en runtime,
/// pero quede listo para v2 (chat tutor, evaluación de pronunciación, etc.).
abstract class AiClient {
  Future<String> chat(String prompt, {String? systemPrompt});
  Future<PronunciationFeedback> evaluatePronunciation(
    String audioPath,
    String reference,
  );
  Future<String> explainAnswer({
    required String question,
    required String userAnswer,
  });
}

class PronunciationFeedback {
  const PronunciationFeedback({
    required this.score,
    required this.transcript,
    required this.suggestions,
  });
  final double score;
  final String transcript;
  final List<String> suggestions;
}

class NotImplementedAiClient implements AiClient {
  const NotImplementedAiClient();

  @override
  Future<String> chat(String prompt, {String? systemPrompt}) {
    throw UnimplementedError('AiClient no configurado en MVP');
  }

  @override
  Future<PronunciationFeedback> evaluatePronunciation(
    String audioPath,
    String reference,
  ) {
    throw UnimplementedError('AiClient no configurado en MVP');
  }

  @override
  Future<String> explainAnswer({
    required String question,
    required String userAnswer,
  }) {
    throw UnimplementedError('AiClient no configurado en MVP');
  }
}
