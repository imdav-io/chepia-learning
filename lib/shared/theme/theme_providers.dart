import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/presentation/controllers/onboarding_providers.dart';
import 'app_theme.dart';
import 'level_style.dart';

/// Reads the user's selected level from onboarding state and maps it to
/// a [LevelStyle]. Defaults to balanced while onboarding is loading or
/// when the user hasn't picked a level yet.
final activeLevelStyleProvider = Provider<LevelStyle>((ref) {
  final onboarding = ref.watch(onboardingStateProvider);
  return onboarding.maybeWhen(
    data: (state) => levelStyleForCode(state.selectedLevelCode),
    orElse: () => LevelStyle.balanced,
  );
});

final activeThemeProvider = Provider<ThemeData>((ref) {
  final style = ref.watch(activeLevelStyleProvider);
  return AppTheme.forStyle(style);
});
