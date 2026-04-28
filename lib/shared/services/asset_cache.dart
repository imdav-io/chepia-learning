import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';

/// Caché simple de bytes para PDFs (y cualquier asset binario).
///
/// - **Mobile**: persiste en `ApplicationDocumentsDirectory/chepia_cache/<kind>/`.
///   Por la `key` (storage_path) se infiere el filename, así URLs firmadas que
///   cambien (TTL) no invalidan el cache.
/// - **Web**: usa una caché en memoria por sesión + se apoya en el cache HTTP
///   del navegador. No persiste entre recargas de pestaña.
class AssetCache {
  AssetCache({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final Map<String, Uint8List> _memCache = {};

  /// Devuelve los bytes del asset. Usa caché si existe; si no, descarga y
  /// guarda. Si la descarga falla, levanta el error de Dio.
  Future<Uint8List> getOrDownload({
    required String key,
    required String url,
    String kind = 'misc',
  }) async {
    if (kIsWeb) {
      final hit = _memCache[key];
      if (hit != null) {
        try {
          return Uint8List.fromList(hit);
        } catch (e, st) {
          AppLogger.warn('AssetCache web hit detached, redownloading', e, st);
          _memCache.remove(key);
        }
      }
      final bytes = await _download(url);
      _memCache[key] = Uint8List.fromList(bytes);
      return Uint8List.fromList(bytes);
    }

    // Mobile / desktop
    final file = await _fileForKey(key, kind);
    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          AppLogger.debug('AssetCache hit: $key (${bytes.length} bytes)');
          return bytes;
        }
      } catch (e, st) {
        AppLogger.warn('AssetCache read failed, redownloading', e, st);
      }
    }

    final bytes = await _download(url);
    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      AppLogger.debug('AssetCache stored: $key (${bytes.length} bytes)');
    } catch (e, st) {
      AppLogger.warn('AssetCache write failed', e, st);
    }
    return bytes;
  }

  Future<bool> exists(String key, {String kind = 'misc'}) async {
    if (kIsWeb) return _memCache.containsKey(key);
    final file = await _fileForKey(key, kind);
    return file.exists();
  }

  Future<void> evict(String key, {String kind = 'misc'}) async {
    if (kIsWeb) {
      _memCache.remove(key);
      return;
    }
    final file = await _fileForKey(key, kind);
    if (await file.exists()) await file.delete();
  }

  Future<int> sizeBytes() async {
    if (kIsWeb) {
      return _memCache.values.fold<int>(0, (sum, b) => sum + b.length);
    }
    final dir = await _cacheDir();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final stat = await entity.stat();
        total += stat.size;
      }
    }
    return total;
  }

  Future<void> clear() async {
    _memCache.clear();
    if (kIsWeb) return;
    final dir = await _cacheDir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<Uint8List> _download(String url) async {
    final res = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }

  Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'chepia_cache'));
  }

  Future<File> _fileForKey(String key, String kind) async {
    final dir = await _cacheDir();
    final hash = sha1.convert(key.codeUnits).toString();
    final ext = p.extension(key).isEmpty ? '.bin' : p.extension(key);
    return File(p.join(dir.path, kind, '$hash$ext'));
  }
}
