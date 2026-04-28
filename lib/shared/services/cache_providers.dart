import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'asset_cache.dart';

final assetCacheProvider = Provider<AssetCache>((ref) {
  return AssetCache();
});
