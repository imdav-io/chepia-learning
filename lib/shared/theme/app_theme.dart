import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'level_style.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light({LevelStyle style = LevelStyle.balanced}) =>
      _build(LevelPalette.forStyle(style));

  static ThemeData dark({LevelStyle style = LevelStyle.balanced}) =>
      _build(LevelPalette.forStyle(style));

  static ThemeData forStyle(LevelStyle style) =>
      _build(LevelPalette.forStyle(style));

  static ThemeData _build(LevelPalette palette) {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimaryDark,
      displayColor: AppColors.textPrimaryDark,
    );

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: palette.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: palette.primary,
          onPrimary: palette.onPrimary,
          primaryContainer: palette.primaryContainer,
          onPrimaryContainer: palette.onPrimaryContainer,
          secondary: palette.secondary,
          onSecondary: palette.onSecondary,
          secondaryContainer: palette.secondaryContainer,
          onSecondaryContainer: palette.onSecondaryContainer,
          tertiary: palette.tertiary,
          onTertiary: palette.onTertiary,
          tertiaryContainer: palette.tertiaryContainer,
          onTertiaryContainer: palette.onTertiaryContainer,
          surface: palette.surface,
          surfaceContainerLowest: palette.background,
          surfaceContainerLow: palette.surface,
          surfaceContainer: palette.surfaceContainer,
          surfaceContainerHigh: palette.surfaceContainerHigh,
          surfaceContainerHighest: palette.surfaceContainerHighest,
          onSurface: AppColors.textPrimaryDark,
          onSurfaceVariant: AppColors.textSecondaryDark,
          outline: palette.outline,
          outlineVariant: palette.outlineVariant,
          error: AppColors.error,
        );

    final titleStyle = GoogleFonts.nunito(
      fontWeight: FontWeight.w900,
      color: AppColors.textPrimaryDark,
    );
    final buttonText = GoogleFonts.nunito(
      fontWeight: FontWeight.w900,
      fontSize: 16,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      dividerColor: palette.outline,
      textTheme: textTheme.copyWith(
        displaySmall: titleStyle.copyWith(fontSize: 36),
        headlineMedium: titleStyle.copyWith(fontSize: 30),
        headlineSmall: titleStyle.copyWith(fontSize: 24),
        titleLarge: titleStyle.copyWith(fontSize: 22),
        titleMedium: titleStyle.copyWith(fontSize: 18),
        titleSmall: titleStyle.copyWith(fontSize: 15),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimaryDark,
          fontWeight: FontWeight.w600,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondaryDark,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: AppColors.textPrimaryDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: titleStyle.copyWith(fontSize: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: palette.surface,
        indicatorColor: palette.primary.withValues(alpha: 0.18),
        shadowColor: palette.primary.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? palette.primary : AppColors.textSecondaryDark,
            size: selected ? 28 : 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.nunito(
            color: selected ? palette.primary : AppColors.textSecondaryDark,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 12,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          foregroundColor: palette.primary,
          side: BorderSide(color: palette.primary.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w900),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
        prefixIconColor: palette.primary,
        suffixIconColor: AppColors.textSecondaryDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.primary, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.primary.withValues(alpha: 0.16)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.primary,
        textColor: AppColors.textPrimaryDark,
        subtitleTextStyle: GoogleFonts.nunito(
          color: AppColors.textSecondaryDark,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: palette.primary.withValues(alpha: 0.18),
        disabledColor: colorScheme.surfaceContainerHigh,
        labelStyle: GoogleFonts.nunito(
          color: AppColors.textPrimaryDark,
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide(color: palette.primary.withValues(alpha: 0.18)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: palette.secondary,
        overlayColor: palette.primary.withValues(alpha: 0.16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surface,
        modalBarrierColor: const Color(0xCC000000),
        dragHandleColor: palette.primary,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
    );
  }
}
