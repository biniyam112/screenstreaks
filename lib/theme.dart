import 'package:flutter/material.dart';

import 'colors.dart';

export 'colors.dart';

/// Brand font family, bundled locally in assets/fonts (see pubspec.yaml).
/// Bundling means it always renders — no runtime network fetch like
/// google_fonts, which silently falls back to an ugly system font when the
/// device is offline or the build lacks the INTERNET permission.
const String kFontFamily = 'PlusJakartaSans';

/// Text style in the brand font.
///
/// [PlusJakartaSans] is a variable font, so we drive the weight through both
/// [fontWeight] and a `wght` [FontVariation] to guarantee the right weight
/// renders on every platform.
TextStyle appFont({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
  double? height,
  TextDecoration? decoration,
}) {
  final weight = fontWeight ?? FontWeight.w400;
  return TextStyle(
    fontFamily: kFontFamily,
    fontSize: fontSize,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
    decoration: decoration,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
  );
}

/// Monospaced-feeling style for share codes: brand font with tabular figures
/// and generous tracking. Avoids depending on a networked mono font.
TextStyle appMono({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
}) =>
    appFont(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

class AppTheme {
  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: const Color(0xFF0B0B0D),
        surface: const Color(0xFF161619),
        text: const Color(0xFFF4F4F6),
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: const Color(0xFFF4F5F7),
        surface: Colors.white,
        text: const Color(0xFF16161A),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color text,
  }) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: kFontFamily,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        brightness: brightness,
        surface: surface,
      ),
      textTheme: base.textTheme
          .apply(
            fontFamily: kFontFamily,
            bodyColor: text,
            displayColor: text,
          ),
      appBarTheme: AppBarTheme(
        // Transparent so the gradient runs unbroken from the status bar to
        // the nav bar, rather than being framed by two solid strips.
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: text,
        titleTextStyle: appFont(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      splashFactory: NoSplash.splashFactory,
    );
  }
}

String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
