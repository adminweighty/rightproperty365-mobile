import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';
import 'tokens.dart';

/// Headings and prices. The brand is sans-serif only, so hierarchy comes from
/// weight and size (design/foundations/typography.md). The brand typeface is
/// Inter; its font files are not bundled yet, so the platform sans is used
/// (Roboto on Android, San Francisco on iOS).
TextStyle displayStyle(Color color, double size) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w700,
  letterSpacing: -0.02 * size,
  height: 1.2,
  color: color,
);

abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.primaryInk,
      secondary: c.accent,
      onSecondary: c.ink,
      secondaryContainer: c.accentSoft,
      onSecondaryContainer: c.accentInk,
      error: c.danger,
      onError: c.onInverse,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      outline: c.control,
      outlineVariant: c.line,
      inverseSurface: c.inverse,
      onInverseSurface: c.onInverse,
      surfaceTint: Colors.transparent,
    );

    // Sizes follow design/foundations/typography.md. Body and inputs are 16.
    final text = TextTheme(
      displaySmall: displayStyle(c.ink, 36),
      headlineMedium: displayStyle(c.ink, 30),
      headlineSmall: displayStyle(c.ink, 24),
      titleLarge: displayStyle(c.ink, 20),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: c.ink,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: c.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: c.ink,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: c.muted,
      ),
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.md),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.page,
      textTheme: text,
      extensions: [c],
      // 48dp minimum touch targets everywhere.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.page,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: displayStyle(c.ink, 20),
        shape: Border(bottom: BorderSide(color: c.line)),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: c.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: controlShape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          foregroundColor: c.ink,
          side: BorderSide(color: c.lineStrong),
          shape: controlShape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: c.primaryInk,
          shape: controlShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: c.subtle),
        helperStyle: TextStyle(color: c.muted, fontSize: 14),
        errorStyle: TextStyle(color: c.danger, fontSize: 14),
        helperMaxLines: 3,
        errorMaxLines: 3,
        border: inputBorder(c.control),
        enabledBorder: inputBorder(c.control),
        focusedBorder: inputBorder(c.focus, 2),
        errorBorder: inputBorder(c.danger),
        focusedErrorBorder: inputBorder(c.danger, 2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.primarySoft,
        side: BorderSide(color: c.lineStrong),
        labelStyle: TextStyle(fontSize: 14, color: c.ink),
        checkmarkColor: c.primaryInk,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.full),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primarySoft,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? c.primaryInk
                : c.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? c.primaryInk
                : c.muted,
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: c.control, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    );
  }
}
