import 'package:flutter/material.dart';

/// Shared visual language for FireCheck's field workflows.
ThemeData buildAppTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB93228),
  ).copyWith(
    primary: const Color(0xFFB93228),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFFCF0EE),
    onPrimaryContainer: const Color(0xFF85261F),
    secondary: const Color(0xFF286B61),
    tertiary: const Color(0xFF946A17),
    surface: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFFAFAFA),
    surfaceContainer: const Color(0xFFF6F7F7),
    surfaceContainerHigh: const Color(0xFFF1F3F3),
    surfaceContainerHighest: const Color(0xFFECEFEF),
    onSurface: const Color(0xFF24282B),
    onSurfaceVariant: const Color(0xFF596166),
    outline: const Color(0xFFC6CDCF),
    outlineVariant: const Color(0xFFE7EAEA),
    error: const Color(0xFFB3261E),
    errorContainer: const Color(0xFFFFF3F2),
  );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  final base =
      ThemeData(useMaterial3: true, colorScheme: colors, fontFamily: 'Roboto');
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    textTheme: base.textTheme
        .copyWith(
          headlineLarge: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 32,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
          headlineMedium: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 28,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineSmall: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 24,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 17,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge:
              const TextStyle(fontFamily: 'Roboto', fontSize: 16, height: 1.45),
          bodyMedium:
              const TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.4),
          bodySmall: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 13,
            height: 1.4,
            color: colors.onSurfaceVariant,
          ),
        )
        .apply(
            fontFamily: 'Roboto',
            bodyColor: colors.onSurface,
            displayColor: colors.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      titleSpacing: 24,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: shape.copyWith(side: BorderSide(color: colors.outlineVariant)),
    ),
    dividerTheme:
        DividerThemeData(color: colors.outlineVariant, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      iconColor: colors.onSurfaceVariant,
      horizontalTitleGap: 16,
      minVerticalPadding: 12,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: colors.onSurface,
      ),
      subtitleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          height: 1.4,
          color: colors.onSurfaceVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      labelStyle: TextStyle(
          fontFamily: 'Roboto', fontSize: 14, color: colors.onSurfaceVariant),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
            fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
        shape: shape,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        textStyle: const TextStyle(
            fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: colors.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: colors.outline),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(
            fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 76,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 26,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: colors.primary,
      unselectedLabelColor: colors.onSurfaceVariant,
      indicatorColor: colors.primary,
      dividerColor: colors.outlineVariant,
      labelStyle: const TextStyle(
          fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
          fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w400),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      iconColor: colors.primary,
      collapsedIconColor: colors.onSurfaceVariant,
      textColor: colors.onSurface,
      collapsedTextColor: colors.onSurface,
      tilePadding: const EdgeInsets.symmetric(vertical: 12),
      childrenPadding: const EdgeInsets.only(bottom: 24),
      shape: Border(top: BorderSide(color: colors.outlineVariant)),
      collapsedShape: Border(top: BorderSide(color: colors.outlineVariant)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: colors.surfaceContainerLow,
      selectedColor: colors.primaryContainer,
      side: BorderSide(color: colors.outlineVariant),
      shape: shape,
      labelStyle: TextStyle(
          fontFamily: 'Roboto', fontSize: 13, color: colors.onSurfaceVariant),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.surfaceContainerHighest,
      linearMinHeight: 6,
      borderRadius: BorderRadius.circular(8),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.onSurface,
      shape: shape,
    ),
  );
}
