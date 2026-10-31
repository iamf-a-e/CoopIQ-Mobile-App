import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Single place to match the website palette. Swap the hex values below with
/// the exact tokens from the site's CSS and the whole app follows.
class CoopColors {
  static const forest = Color(0xFF1E4D36);
  static const leaf = Color(0xFF3F8F5B);
  static const amber = Color(0xFFE9A63A);
  static const ink = Color(0xFF16231C);
  static const paper = Color(0xFFF5F7F2);
  static const card = Color(0xFFFFFFFF);
  static const alert = Color(0xFFC2452D);
  static const muted = Color(0xFF66766C);

  // Links (brown so they stand out on the green/white screens).
  static const brown = Color(0xFF7A4A21);
  static const brownLight = Color(0xFFE0A972); // brown on dark backgrounds

  // Dark mode surfaces and text.
  static const darkPaper = Color(0xFF0F1A14);
  static const darkCard = Color(0xFF17251D);
  static const darkInk = Color(0xFFE6EEE8);
  static const darkMuted = Color(0xFF9FB0A5);
  static const darkLine = Color(0xFF2A3B31);
  static const brandOnDark = Color(0xFF7CC796); // forest, lightened for dark
  static const alertOnDark = Color(0xFFE57A62);
}

/// Colors that change with light/dark mode. Use these in widgets instead of
/// the fixed CoopColors where the color is used for text or icons.
extension CoopContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get brand => isDark ? CoopColors.brandOnDark : CoopColors.forest;
  Color get muted => isDark ? CoopColors.darkMuted : CoopColors.muted;
  Color get link => isDark ? CoopColors.brownLight : CoopColors.brown;
  Color get danger => isDark ? CoopColors.alertOnDark : CoopColors.alert;
  Color get cardBg => isDark ? CoopColors.darkCard : CoopColors.card;
  Color get lineColor => isDark ? CoopColors.darkLine : const Color(0xFFD5DDD0);
}

ThemeData buildTheme() => _build(Brightness.light);
ThemeData buildDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness b) {
  final dark = b == Brightness.dark;
  final paper = dark ? CoopColors.darkPaper : CoopColors.paper;
  final card = dark ? CoopColors.darkCard : CoopColors.card;
  final ink = dark ? CoopColors.darkInk : CoopColors.ink;
  final line = dark ? CoopColors.darkLine : const Color(0xFFD5DDD0);

  final scheme = ColorScheme.fromSeed(
    seedColor: CoopColors.forest,
    brightness: b,
    primary: dark ? CoopColors.leaf : CoopColors.forest,
    onPrimary: Colors.white,
    secondary: CoopColors.amber,
    surface: paper,
    onSurface: ink,
    error: dark ? CoopColors.alertOnDark : CoopColors.alert,
  );

  final base = GoogleFonts.dmSansTextTheme();
  final text = base
      .copyWith(
        headlineLarge: GoogleFonts.fraunces(textStyle: base.headlineLarge, fontWeight: FontWeight.w600),
        headlineMedium: GoogleFonts.fraunces(textStyle: base.headlineMedium, fontWeight: FontWeight.w600),
        headlineSmall: GoogleFonts.fraunces(textStyle: base.headlineSmall, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.fraunces(textStyle: base.titleLarge, fontWeight: FontWeight.w600),
      )
      .apply(bodyColor: ink, displayColor: ink);

  final border = BorderSide(color: line);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
      foregroundColor: ink,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? CoopColors.darkLine : const Color(0xFFE1E7DD)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? CoopColors.darkCard : Colors.white,
      indicatorColor: (dark ? CoopColors.leaf : CoopColors.forest).withAlpha(dark ? 70 : 30),
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: border),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: border),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? CoopColors.leaf : CoopColors.forest,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
  );
}
