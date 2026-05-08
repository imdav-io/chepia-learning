import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/asset.dart';

/// Resuelve la URL final de un asset, ya sea absoluta (demo / CDN) o
/// firmada desde Supabase Storage.
class AssetRepository {
  AssetRepository(
    this._client, {
    this.bucket = 'content',
    this.signedSeconds = 3600,
  });

  final SupabaseClient _client;
  final String bucket;
  final int signedSeconds;

  Future<String> resolveUrl(Asset asset) async {
    if (asset.isAbsoluteUrl) return asset.storagePath;
    try {
      final url = await _client.storage
          .from(bucket)
          .createSignedUrl(asset.storagePath, signedSeconds);
      return url;
    } catch (e, st) {
      AppLogger.error('createSignedUrl failed for ${asset.storagePath}', e, st);
      throw StorageFailure('No se pudo obtener la URL del archivo', cause: e);
    }
  }
}
