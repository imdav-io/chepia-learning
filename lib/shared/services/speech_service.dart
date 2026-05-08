import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechSessionResult {
  const SpeechSessionResult({
    required this.transcript,
    required this.confidence,
    required this.finalResult,
  });

  final String transcript;
  final double confidence;
  final bool finalResult;
}

class SpeechService {
  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _available = false;
  StreamController<SpeechSessionResult>? _activeController;

  bool get isListening => _stt.isListening;

  Future<bool> ensureInitialized() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _stt.initialize(
        onError: (e) {
          if (kDebugMode) debugPrint('SpeechService error: ${e.errorMsg}');
          unawaited(_closeActiveSession());
        },
        onStatus: (s) {
          if (kDebugMode) debugPrint('SpeechService status: $s');
          if (s == 'done' || s == 'notListening') {
            unawaited(_closeActiveSession());
          }
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('SpeechService init failed: $e');
      _available = false;
    }
    return _available;
  }

  /// Listens until silence or [timeout]. Streams partial + final results.
  Stream<SpeechSessionResult> listen({
    String localeId = 'en_US',
    Duration timeout = const Duration(seconds: 8),
    Duration pauseAfter = const Duration(seconds: 2),
  }) {
    final controller = StreamController<SpeechSessionResult>();
    Timer? hardStopTimer;

    Future<void> closeSession() async {
      hardStopTimer?.cancel();
      if (_activeController == controller) {
        _activeController = null;
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    }

    Future<void> start() async {
      final ok = await ensureInitialized();
      if (!ok) {
        await controller.close();
        return;
      }
      try {
        await _stt.stop();
        _activeController = controller;
        hardStopTimer = Timer(
          timeout + pauseAfter + const Duration(seconds: 1),
          () {
            unawaited(stop());
          },
        );
        await _stt.listen(
          localeId: localeId,
          listenFor: timeout,
          pauseFor: pauseAfter,
          onResult: (SpeechRecognitionResult res) {
            if (controller.isClosed) return;
            final confidence = res.alternates.isEmpty
                ? 0.0
                : res.alternates.first.confidence;
            controller.add(
              SpeechSessionResult(
                transcript: res.recognizedWords,
                confidence: confidence,
                finalResult: res.finalResult,
              ),
            );
            if (res.finalResult) unawaited(closeSession());
          },
          listenOptions: SpeechListenOptions(
            partialResults: true,
            cancelOnError: true,
            listenMode: ListenMode.confirmation,
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('SpeechService listen failed: $e');
        await closeSession();
      }
    }

    controller.onCancel = () async {
      hardStopTimer?.cancel();
      if (_activeController == controller) {
        _activeController = null;
      }
      try {
        await _stt.stop();
      } catch (_) {}
    };

    unawaited(start());
    return controller.stream;
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
    await _closeActiveSession();
  }

  Future<void> _closeActiveSession() async {
    final controller = _activeController;
    _activeController = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }
}

final speechServiceProvider = Provider<SpeechService>((ref) {
  final service = SpeechService();
  ref.onDispose(service.stop);
  return service;
});

/// Normalizes a string for comparison: lowercases, strips punctuation,
/// collapses whitespace.
String normalizeForSpeech(String input) {
  final lowered = input.toLowerCase();
  final stripped = lowered.replaceAll(RegExp(r"[^a-z0-9' ]"), ' ');
  return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Returns 0.0–1.0 similarity between expected and heard transcript.
/// Uses Levenshtein distance on the word level + character fallback.
double pronunciationScore({required String expected, required String heard}) {
  final exp = normalizeForSpeech(expected);
  final got = normalizeForSpeech(heard);
  if (exp.isEmpty) return 0;
  if (got.isEmpty) return 0;
  if (exp == got) return 1;

  final expWords = exp.split(' ');
  final gotWords = got.split(' ');
  final wordDist = _levenshtein(expWords, gotWords);
  final wordScore = 1 - (wordDist / max(expWords.length, gotWords.length));

  final charDist = _levenshteinChars(exp, got);
  final charScore = 1 - (charDist / max(exp.length, got.length));

  return ((wordScore * 0.6) + (charScore * 0.4)).clamp(0.0, 1.0);
}

int _levenshtein(List<String> a, List<String> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    dp[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce(min);
    }
  }
  return dp[n][m];
}

int _levenshteinChars(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    dp[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce(min);
    }
  }
  return dp[n][m];
}
