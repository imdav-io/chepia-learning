import 'package:flutter/material.dart';

enum LevelStyle { vivid, balanced, sober }

class LevelPalette {
  const LevelPalette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.background,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
    required this.onPrimary,
    required this.onSecondary,
    required this.onTertiary,
    required this.primaryContainer,
    required this.secondaryContainer,
    required this.tertiaryContainer,
    required this.onPrimaryContainer,
    required this.onSecondaryContainer,
    required this.onTertiaryContainer,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color background;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color outline;
  final Color outlineVariant;
  final Color onPrimary;
  final Color onSecondary;
  final Color onTertiary;
  final Color primaryContainer;
  final Color secondaryContainer;
  final Color tertiaryContainer;
  final Color onPrimaryContainer;
  final Color onSecondaryContainer;
  final Color onTertiaryContainer;

  static const LevelPalette vivid = LevelPalette(
    primary: Color(0xFFFFB020),
    onPrimary: Color(0xFF2A1700),
    primaryContainer: Color(0xFF5A3A00),
    onPrimaryContainer: Color(0xFFFFE9B0),
    secondary: Color(0xFFFF5C8A),
    onSecondary: Color(0xFF2A0414),
    secondaryContainer: Color(0xFF591131),
    onSecondaryContainer: Color(0xFFFFD9E4),
    tertiary: Color(0xFFA78BFA),
    onTertiary: Color(0xFF1F0E45),
    tertiaryContainer: Color(0xFF3F2A78),
    onTertiaryContainer: Color(0xFFE9DDFF),
    background: Color(0xFF12081C),
    surface: Color(0xFF18102A),
    surfaceContainer: Color(0xFF1D1432),
    surfaceContainerHigh: Color(0xFF231A3D),
    surfaceContainerHighest: Color(0xFF2C2349),
    outline: Color(0xFF453560),
    outlineVariant: Color(0xFF2D213F),
  );

  static const LevelPalette balanced = LevelPalette(
    primary: Color(0xFF35DCEB),
    onPrimary: Color(0xFF021417),
    primaryContainer: Color(0xFF073A47),
    onPrimaryContainer: Color(0xFFE5FCFF),
    secondary: Color(0xFF2AF08C),
    onSecondary: Color(0xFF03160B),
    secondaryContainer: Color(0xFF093D25),
    onSecondaryContainer: Color(0xFFE2FFEF),
    tertiary: Color(0xFFE655FF),
    onTertiary: Color(0xFF1A0620),
    tertiaryContainer: Color(0xFF401349),
    onTertiaryContainer: Color(0xFFFDE7FF),
    background: Color(0xFF050712),
    surface: Color(0xFF0B1020),
    surfaceContainer: Color(0xFF0B1020),
    surfaceContainerHigh: Color(0xFF10182A),
    surfaceContainerHighest: Color(0xFF142033),
    outline: Color(0xFF213445),
    outlineVariant: Color(0xFF17283A),
  );

  static const LevelPalette sober = LevelPalette(
    primary: Color(0xFF6FA8DC),
    onPrimary: Color(0xFF06121F),
    primaryContainer: Color(0xFF1A2E45),
    onPrimaryContainer: Color(0xFFD8E5F4),
    secondary: Color(0xFF8FB8A6),
    onSecondary: Color(0xFF0A1611),
    secondaryContainer: Color(0xFF1B2E26),
    onSecondaryContainer: Color(0xFFD9E8E0),
    tertiary: Color(0xFFB0A4C2),
    onTertiary: Color(0xFF120E1A),
    tertiaryContainer: Color(0xFF2A2335),
    onTertiaryContainer: Color(0xFFE3DCEE),
    background: Color(0xFF080C12),
    surface: Color(0xFF0E131C),
    surfaceContainer: Color(0xFF111722),
    surfaceContainerHigh: Color(0xFF161D2A),
    surfaceContainerHighest: Color(0xFF1B2331),
    outline: Color(0xFF2A3344),
    outlineVariant: Color(0xFF1A2230),
  );

  static LevelPalette forStyle(LevelStyle style) => switch (style) {
    LevelStyle.vivid => vivid,
    LevelStyle.balanced => balanced,
    LevelStyle.sober => sober,
  };
}

LevelStyle levelStyleForCode(String? code) => switch (code) {
  'beginner' => LevelStyle.vivid,
  'intermediate' => LevelStyle.balanced,
  'advanced' => LevelStyle.sober,
  _ => LevelStyle.balanced,
};
