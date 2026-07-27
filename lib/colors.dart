import 'package:flutter/material.dart';

/// Brand colors — identical in both themes.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF10B981); // emerald
  static const primaryDim = Color(0xFF0C9E6E);
  static const accent = Color(0xFFFB8C3C); // streak / fire orange
  static const danger = Color(0xFFF0524B);
  static const info = Color(0xFF4C8DF6); // blue
  static const warning = Color(0xFFF5A623);
}

/// Theme-aware neutral colors. Read them from a [BuildContext] so the same
/// widget renders correctly in dark and light mode.
extension AppColorsX on BuildContext {
  bool get _dark => Theme.of(this).brightness == Brightness.dark;

  /// App scaffold background.
  Color get cBg => _dark ? const Color(0xFF0B0B0D) : const Color(0xFFF4F5F7);

  /// Card / raised surface.
  Color get cSurface => _dark ? const Color(0xFF161619) : Colors.white;

  /// Inner / elevated surface (chips, wells inside cards).
  Color get cSurfaceHi =>
      _dark ? const Color(0xFF202027) : const Color(0xFFEFF1F4);

  Color get cText => _dark ? const Color(0xFFF4F4F6) : const Color(0xFF16161A);
  Color get cTextSec =>
      _dark ? const Color(0xFF9A9AA4) : const Color(0xFF5A5A66);
  Color get cTextTer =>
      _dark ? const Color(0xFF5E5E68) : const Color(0xFF9A9AA6);
  Color get cDivider =>
      _dark ? const Color(0xFF26262B) : const Color(0xFFE6E7EC);
}
