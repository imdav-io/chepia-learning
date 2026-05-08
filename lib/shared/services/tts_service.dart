import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around FlutterTts that targets US English by default.
/// Designed to be reused across vocabulary, reader and quiz flows.
class TtsService {
  TtsService() {
    _init();
  }

  final FlutterTts _tts = FlutterTts();
  Future<void>? _initFuture;
  bool _ready = false;

  Future<void> _init() async {
    _initFuture ??= _doInit();
    return _initFuture;
  }

  Future<void> _doInit() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _ready = true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('TtsService init failed: $e\n$st');
      }
    }
  }

  /// Speaks [text] using current settings. Returns when speech completes.
  Future<void> speak(String text, {double rate = 0.45}) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await _init();
    if (!_ready) return;
    try {
      await _tts.stop();
      await _tts.setSpeechRate(rate);
      await _tts.speak(value);
    } catch (e) {
      if (kDebugMode) debugPrint('TtsService speak failed: $e');
    }
  }

  Future<void> stop() async {
    if (!_ready) return;
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  ref.onDispose(service.stop);
  return service;
});
