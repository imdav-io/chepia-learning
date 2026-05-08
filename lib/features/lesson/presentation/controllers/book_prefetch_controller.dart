import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../shared/services/asset_cache.dart';
import '../../../../shared/services/cache_providers.dart';
import '../../../catalog/presentation/controllers/catalog_providers.dart';

class BookPrefetchState {
  const BookPrefetchState({
    this.total = 0,
    this.completed = 0,
    this.skipped = 0,
    this.failed = 0,
    this.currentLabel,
    this.isRunning = false,
    this.isFinished = false,
    this.startedFor,
  });

  final int total;
  final int completed;
  final int skipped;
  final int failed;
  final String? currentLabel;
  final bool isRunning;
  final bool isFinished;

  /// Identidad del set de assets sobre el que arrancó la corrida actual.
  /// Permite detectar cuando llegan datos nuevos (otro libro, manifest fresco)
  /// y reiniciar sin tocar el estado del usuario.
  final String? startedFor;

  int get processed => completed + skipped + failed;
  double get progress => total == 0 ? 0 : processed / total;

  /// Visible solo si hay descargas reales en curso. Si todo estaba cacheado
  /// no molestamos al usuario con un banner.
  bool get shouldShowBanner =>
      isRunning && total > 0 && total != skipped + processed;

  BookPrefetchState copyWith({
    int? total,
    int? completed,
    int? skipped,
    int? failed,
    String? currentLabel,
    bool clearLabel = false,
    bool? isRunning,
    bool? isFinished,
    String? startedFor,
  }) {
    return BookPrefetchState(
      total: total ?? this.total,
      completed: completed ?? this.completed,
      skipped: skipped ?? this.skipped,
      failed: failed ?? this.failed,
      currentLabel: clearLabel ? null : (currentLabel ?? this.currentLabel),
      isRunning: isRunning ?? this.isRunning,
      isFinished: isFinished ?? this.isFinished,
      startedFor: startedFor ?? this.startedFor,
    );
  }
}

class BookPrefetchController extends StateNotifier<BookPrefetchState> {
  BookPrefetchController(this._cache) : super(const BookPrefetchState());

  final AssetCache _cache;
  bool _cancelled = false;

  /// Asegura que un prefetch esté corriendo para [assets]. Si ya hay uno en
  /// curso para los mismos assets, no hace nada. Si llegan assets nuevos
  /// (signature diferente), cancela el anterior y arranca de nuevo.
  Future<void> ensureRunning({
    required String bookSlug,
    required List<BookOfflineAsset> assets,
  }) async {
    final signature = _signatureFor(bookSlug, assets);
    if (state.startedFor == signature && (state.isRunning || state.isFinished)) {
      return;
    }
    _cancelled = false;
    state = BookPrefetchState(
      total: assets.length,
      isRunning: true,
      startedFor: signature,
    );
    if (assets.isEmpty) {
      state = state.copyWith(isRunning: false, isFinished: true);
      return;
    }
    for (final asset in assets) {
      if (_cancelled) return;
      final cached = await _cache.exists(asset.key, kind: asset.kind);
      if (cached) {
        state = state.copyWith(
          skipped: state.skipped + 1,
          clearLabel: true,
        );
        continue;
      }
      state = state.copyWith(currentLabel: asset.label);
      try {
        await _cache.getOrDownload(
          key: asset.key,
          url: asset.url,
          kind: asset.kind,
        );
        if (_cancelled) return;
        state = state.copyWith(completed: state.completed + 1);
      } catch (e, st) {
        AppLogger.warn('book prefetch asset failed: ${asset.label}', e, st);
        state = state.copyWith(failed: state.failed + 1);
      }
    }
    state = state.copyWith(
      isRunning: false,
      isFinished: true,
      clearLabel: true,
    );
  }

  void cancel() {
    _cancelled = true;
    if (state.isRunning) {
      state = state.copyWith(isRunning: false);
    }
  }

  String _signatureFor(String bookSlug, List<BookOfflineAsset> assets) {
    final keys = assets.map((a) => a.key).join('|');
    return '$bookSlug::$keys';
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

final bookPrefetchControllerProvider = StateNotifierProvider.autoDispose
    .family<BookPrefetchController, BookPrefetchState, String>(
      (ref, bookSlug) {
        final cache = ref.watch(assetCacheProvider);
        return BookPrefetchController(cache);
      },
    );
