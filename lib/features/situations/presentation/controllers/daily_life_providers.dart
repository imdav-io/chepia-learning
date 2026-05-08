import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../data/repositories/daily_life_repository.dart';
import '../../domain/entities/daily_life_situation.dart';

final dailyLifeRepositoryProvider = Provider<DailyLifeRepository>((ref) {
  return DailyLifeRepository(ref.watch(supabaseClientProvider));
});

final dailyLifeSituationsProvider = FutureProvider<List<DailyLifeSituation>>((
  ref,
) {
  return ref.watch(dailyLifeRepositoryProvider).fetchSituations();
});

final dailyLifeSituationProvider =
    FutureProvider.family<DailyLifeSituationBundle?, String>((ref, slug) {
      return ref.watch(dailyLifeRepositoryProvider).fetchSituation(slug);
    });
