import 'package:flutter/material.dart';

/// AKERIYAN design system — minimalist "Nothing OS" aesthetic in
/// DARK + SILVER + NEON LIGHT-PURPLE:
///   • pure black canvas
///   • cool silver-white text and secondary accents
///   • one neon light-purple accent for anything active / primary / live
///   • flat surfaces with hairline borders + the NDot dot-matrix display font
///
/// The token NAMES are kept stable (gold/cyan/green/gradients/glass...) so every
/// existing screen restyles automatically — only the values changed. In this
/// scheme the old accent names map to PURPLE and the old secondary names to
/// SILVER.
class Ak {
  // ---- Dot-matrix display font (registered in pubspec as "NDot") ----
  static const String dot = 'NDot';

  // ---- Signature colours ----
  static const purple = Color(0xFFB57BFF);     // neon light-purple accent
  static const purpleSoft = Color(0xFFCDA9FF); // lighter purple
  static const purpleDeep = Color(0xFF7A4FD6); // darker purple (gradient end)
  static const silver = Color(0xFFC7CBD1);     // metallic silver (secondary)

  // ---- Core palette ----
  static const bg0 = Color(0xFF000000); // pure black
  static const bg1 = Color(0xFF0A0A0F); // near-black with a faint cool tint
  static const bg2 = Color(0xFF14141C);

  // Legacy accent names remapped to the new scheme (keeps screens working):
  static const gold = purple;            // primary accent  -> neon purple
  static const amber = purpleSoft;       // lighter purple
  static const orange = purpleDeep;      // darker purple (gradient / glow)
  static const cyan = silver;            // secondary accent -> silver
  static const violet = Color(0xFF9E7BFF); // purple variant
  static const pink = Color(0xFFC77DFF); // alerts -> bright purple (no red)
  static const green = purple;           // live / active / connected -> purple

  static const textHi = Color(0xFFF1F2F6); // bright silver-white
  static const textMid = Color(0xFFA6ADB8); // silver
  static const textLo = Color(0xFF666C76);  // dim silver

  // ---- Market data semantics (trading / scalp / pro screens ONLY) ----
  // Conventional green-up / red-down colours for candles, trend lines, bias,
  // support/resistance, target/stop — kept separate from the purple UI accent
  // so the rest of the app stays monochrome-purple.
  static const up = Color(0xFF2ED47A);   // green  — bullish / up / support / target
  static const down = Color(0xFFF0454B); // red    — bearish / down / resistance / stop

  // Translucent helpers (hairline borders / flat fills on black)
  static const glassFill = Color(0x0DFFFFFF);       // ~5% white
  static const glassLine = Color(0x1FFFFFFF);       // ~12% white
  static const glassFillStrong = Color(0x14FFFFFF); // ~8% white

  // ---- Gradients (kept subtle/flat, minimalist) ----
  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg0, bg1, bg0],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purple, purpleDeep], // neon purple for the primary button / orb
  );

  static const cyanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2C2E36), Color(0xFF16181E)], // dark silver (secondary)
  );

  // ---- Flat surface with a hairline border (no glassmorphism) ----
  static BoxDecoration glass({double radius = 14, Color? tint}) =>
      BoxDecoration(
        color: tint ?? glassFill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glassLine),
      );

  static List<BoxShadow> glow(Color c, {double blur = 40, double spread = 0}) =>
      [BoxShadow(color: c, blurRadius: blur, spreadRadius: spread)];

  // ---- Dot-matrix display text helper ----
  static TextStyle display({
    double size = 20,
    Color color = textHi,
    double spacing = 2,
    FontWeight weight = FontWeight.w400,
  }) =>
      TextStyle(
        fontFamily: dot,
        fontSize: size,
        color: color,
        letterSpacing: spacing,
        fontWeight: weight,
        height: 1.1,
      );

  // ---- Theme ----
  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: purple,
      secondary: silver,
      surface: bg1,
      error: pink,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg0,
      fontFamily: 'Roboto', // clean, readable body text
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: dot, // dot-matrix for the app bar title
          color: textHi,
          fontSize: 22,
          letterSpacing: 3,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: glassFill,
        side: const BorderSide(color: glassLine),
        labelStyle: const TextStyle(color: textHi, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: textHi),
        bodySmall: TextStyle(color: textLo),
      ),
    );
  }
}
