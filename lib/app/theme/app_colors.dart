import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Semantic colours (tokens.json `theme.light` / `theme.dark`).
///
/// Screens read colours only from here: `context.colors.muted`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.page,
    required this.surface,
    required this.sunken,
    required this.inverse,
    required this.ink,
    required this.muted,
    required this.subtle,
    required this.onInverse,
    required this.line,
    required this.lineStrong,
    required this.control,
    required this.brand,
    required this.brandDeep,
    required this.onBrand,
    required this.brandAccent,
    required this.brandLogo,
    required this.primary,
    required this.primarySoft,
    required this.primaryInk,
    required this.onPrimary,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.focus,
  });

  final Color page, surface, sunken, inverse;
  final Color ink, muted, subtle, onInverse;
  final Color line, lineStrong, control;

  /// The indigo of large brand moments (the home hero). Same in both themes.
  /// Buttons and links use [primary], which lightens in the dark theme.
  final Color brand, brandDeep, onBrand, brandAccent, brandLogo;
  final Color primary, primarySoft, primaryInk, onPrimary;
  final Color accent, accentSoft, accentInk;
  final Color success, successSoft, warning, warningSoft;
  final Color danger, dangerSoft, info, infoSoft;
  final Color focus;

  static const light = AppColors(
    page: Palette.slate25,
    surface: Palette.white,
    sunken: Palette.slate50,
    inverse: Palette.slate900,
    ink: Palette.slate900,
    muted: Palette.slate600,
    subtle: Palette.slate500,
    onInverse: Palette.slate25,
    line: Palette.slate200,
    lineStrong: Palette.slate300,
    control: Palette.slate450,
    brand: Palette.indigo600,
    brandDeep: Palette.indigo800,
    onBrand: Palette.white,
    brandAccent: Palette.turquoise500,
    brandLogo: Palette.indigo600,
    primary: Palette.indigo600,
    primarySoft: Palette.indigo50,
    primaryInk: Palette.indigo600,
    onPrimary: Palette.white,
    accent: Palette.turquoise500,
    accentSoft: Palette.turquoise50,
    accentInk: Palette.turquoise700,
    success: Color(0xFF276F45),
    successSoft: Color(0xFFE8F3EC),
    warning: Color(0xFF8A5208),
    warningSoft: Color(0xFFFBF1DF),
    danger: Color(0xFFB3372F),
    dangerSoft: Color(0xFFFBEBE9),
    info: Color(0xFF2B5F8A),
    infoSoft: Color(0xFFE8F0F7),
    focus: Palette.indigo500,
  );

  static const dark = AppColors(
    page: Palette.slate900,
    surface: Palette.slate850,
    sunken: Palette.slate950,
    inverse: Palette.slate50,
    ink: Palette.slate50,
    muted: Palette.slate300,
    subtle: Palette.slate400,
    onInverse: Palette.slate900,
    line: Palette.slate800,
    lineStrong: Palette.slate700,
    control: Palette.slate450,
    brand: Palette.indigo600,
    brandDeep: Palette.indigo800,
    onBrand: Palette.white,
    brandAccent: Palette.turquoise500,
    brandLogo: Palette.white,
    primary: Palette.indigo300,
    primarySoft: Color(0xFF1C1650),
    primaryInk: Palette.indigo200,
    onPrimary: Palette.indigo900,
    accent: Palette.turquoise300,
    accentSoft: Palette.turquoise900,
    accentInk: Palette.turquoise100,
    success: Color(0xFF7CC79A),
    successSoft: Color(0xFF17301F),
    warning: Color(0xFFE8B45C),
    warningSoft: Color(0xFF3A2C10),
    danger: Color(0xFFF0938B),
    dangerSoft: Color(0xFF3D1A17),
    info: Color(0xFF8DB9DE),
    infoSoft: Color(0xFF152B3D),
    focus: Palette.indigo300,
  );

  // The two themes are fixed sets, so there is nothing to override or blend.
  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < 0.5 || other is! AppColors ? this : other;
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
