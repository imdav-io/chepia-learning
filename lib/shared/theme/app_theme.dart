import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() => _neonStudyTheme();

  static ThemeData dark() => _neonStudyTheme();

  static ThemeData _neonStudyTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimaryDark,
      displayColor: AppColors.textPrimaryDark,
    );

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: const Color(0xFF021417),
          primaryContainer: const Color(0xFF073A47),
          onPrimaryContainer: const Color(0xFFE5FCFF),
          secondary: AppColors.secondary,
          onSecondary: const Color(0xFF03160B),
          secondaryContainer: const Color(0xFF093D25),
          onSecondaryContainer: const Color(0xFFE2FFEF),
          tertiary: AppColors.tertiary,
          onTertiary: const Color(0xFF1A0620),
          tertiaryContainer: const Color(0xFF401349),
          onTertiaryContainer: const Color(0xFFFDE7FF),
          surface: AppColors.surfaceDark,
          surfaceContainerLowest: const Color(0xFF050712),
          surfaceContainerLow: const Color(0xFF080D1A),
          surfaceContainer: const Color(0xFF0B1020),
          surfaceContainerHigh: const Color(0xFF10182A),
          surfaceContainerHighest: const Color(0xFF142033),
          onSurface: AppColors.textPrimaryDark,
          onSurfaceVariant: AppColors.textSecondaryDark,
          outline: AppColors.borderDark,
          outlineVariant: const Color(0xFF17283A),
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
      scaffoldBackgroundColor: AppColors.backgroundDark,
      canvasColor: AppColors.backgroundDark,
      dividerColor: AppColors.borderDark,
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
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textPrimaryDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: titleStyle.copyWith(fontSize: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: AppColors.surfaceDark,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        shadowColor: AppColors.primary.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.primary : AppColors.textSecondaryDark,
            size: selected ? 28 : 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.nunito(
            color: selected ? AppColors.primary : AppColors.textSecondaryDark,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 12,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          backgroundColor: AppColors.primary,
          foregroundColor: const Color(0xFF021417),
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
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w900),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
        prefixIconColor: AppColors.primary,
        suffixIconColor: AppColors.textSecondaryDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.16)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.primary,
        textColor: AppColors.textPrimaryDark,
        subtitleTextStyle: GoogleFonts.nunito(
          color: AppColors.textSecondaryDark,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: AppColors.primary.withValues(alpha: 0.18),
        disabledColor: colorScheme.surfaceContainerHigh,
        labelStyle: GoogleFonts.nunito(
          color: AppColors.textPrimaryDark,
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: AppColors.secondary,
        overlayColor: AppColors.primary.withValues(alpha: 0.16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surfaceDark,
        modalBarrierColor: Color(0xCC000000),
        dragHandleColor: AppColors.primary,
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
