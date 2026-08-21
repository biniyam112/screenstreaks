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

  /// App scaffold background. Mostly hidden behind [AppBackground]'s
  /// gradient — this is the fallback where that isn't used.
  Color get cBg => _dark ? const Color(0xFF1E2740) : const Color(0xFFC3B4D6);

  /// The three stops of the background gradient, top to bottom.
  List<Color> get cGradient => _dark
      ? const [Color(0xFF1E2740), Color(0xFF2B2440), Color(0xFF3A2833)]
      : const [Color(0xFF8FA8DC), Color(0xFFC3B4D6), Color(0xFFEFCDD1)];

  /// The soft bloom behind the middle of the screen.
  Color get cBloom => _dark
      ? const Color(0xFFA0B4E6).withValues(alpha: 0.14)
      : Colors.white.withValues(alpha: 0.28);

  /// Card / raised surface. Translucent so the gradient reads through.
  Color get cSurface => _dark
      ? Colors.white.withValues(alpha: 0.07)
      // Thin, so the gradient reads through. The accents below are darkened
      // to compensate rather than the card being made opaque.
      : Colors.white.withValues(alpha: 0.42);

  /// Hairline that keeps a translucent card's edge visible.
  Color get cCardBorder => _dark
      ? Colors.white.withValues(alpha: 0.13)
      : Colors.white.withValues(alpha: 0.55);

  /// Inner / elevated surface (chips, wells inside cards).
  Color get cSurfaceHi =>
      _dark ? const Color(0xFF202027) : const Color(0xFFEFF1F4);

  Color get cText => _dark ? const Color(0xFFF4F4F6) : const Color(0xFF1A1726);
  Color get cTextSec =>
      _dark ? const Color(0xFF9A9CB0) : const Color(0xFF3A3448);
  Color get cTextTer =>
      _dark ? const Color(0xFF6A6A7A) : const Color(0xFF6E6880);
  Color get cDivider => _dark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.45);

  /// Green and red need darkening on the pale gradient to stay legible.
  Color get cGood => _dark ? AppColors.primary : const Color(0xFF064E38);
  Color get cBad => _dark ? AppColors.danger : const Color(0xFFA32A24);
  Color get cWarn => _dark ? AppColors.accent : const Color(0xFF8A3F0C);

  /// Fills like calendar squares and progress bars, which carry white text
  /// and sit on the thin card.
  Color get cGoodFill => _dark ? AppColors.primary : const Color(0xFF0B7A57);
  Color get cBadFill => _dark ? AppColors.danger : const Color(0xFFC4342D);
}
