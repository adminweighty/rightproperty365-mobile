// Straight mirror of design/tokens/tokens.json in the web repository.
//
// Brand colours come from the approved logo kit v4.1: indigo #1900AC and
// turquoise #21DDBA. Keep this file a one-to-one copy of tokens.json (same
// names, same values) so it can be regenerated when the tokens change.
// Screens must not import this file; they read semantic colours from
// AppColors (app_colors.dart).
import 'package:flutter/painting.dart';

abstract final class Palette {
  static const white = Color(0xFFFFFFFF);

  static const slate25 = Color(0xFFF8F9FC);
  static const slate50 = Color(0xFFF1F3F8);
  static const slate100 = Color(0xFFE6E9F0);
  static const slate200 = Color(0xFFD5DAE4);
  static const slate300 = Color(0xFFBCC3D1);
  static const slate400 = Color(0xFF98A1B3);
  static const slate450 = Color(0xFF7C8598);
  static const slate500 = Color(0xFF626B7E);
  static const slate600 = Color(0xFF4F586A);
  static const slate700 = Color(0xFF3A4252);
  static const slate800 = Color(0xFF252B38);
  static const slate850 = Color(0xFF1B202B);
  static const slate900 = Color(0xFF131722);
  static const slate950 = Color(0xFF0C0F17);

  static const indigo50 = Color(0xFFF1EFFF);
  static const indigo100 = Color(0xFFE2DEFF);
  static const indigo200 = Color(0xFFC5BDFF);
  static const indigo300 = Color(0xFFA093FF);
  static const indigo400 = Color(0xFF7A66FF);
  static const indigo500 = Color(0xFF4A2FE0);
  static const indigo600 = Color(0xFF1900AC);
  static const indigo700 = Color(0xFF14008A);
  static const indigo800 = Color(0xFF0F0069);
  static const indigo900 = Color(0xFF0A0047);

  static const turquoise50 = Color(0xFFE9FCF8);
  static const turquoise100 = Color(0xFFC8F7ED);
  static const turquoise300 = Color(0xFF6EEAD3);
  static const turquoise500 = Color(0xFF21DDBA);
  static const turquoise600 = Color(0xFF12B396);
  static const turquoise700 = Color(0xFF0A6F5D);
  static const turquoise900 = Color(0xFF0A3A32);
}

/// tokens.json `radius`, in logical pixels.
abstract final class Radii {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const xl = 20.0;
  static const full = 999.0;
}

/// tokens.json `motion.duration`.
abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
}

/// 4px spacing scale shared with the web (design/foundations/layout.md).
abstract final class Space {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
}
