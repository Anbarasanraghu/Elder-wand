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

  // ---- Signature colours ("Glyph" — obsidian & moonlight, monochrome) ----
  // The only "colour" is luminance: a cool wand-light white for anything alive.
  static const purple = Color(0xFFDFE9FB);     // primary accent -> cool wand-light
  static const purpleSoft = Color(0xFFF4F8FF); // brightest lumen
  static const purpleDeep = Color(0xFF6F80A0); // cool steel (gradient end)
  static const silver = Color(0xFF8B939D);     // cool silver (secondary/structure)
  static const glowOrange = Color(0xFF96BEFF); // cool ambient glow

  // ---- Core palette (obsidian canvas, faint blue bias) ----
  static const bg0 = Color(0xFF070809); // obsidian
  static const bg1 = Color(0xFF0B0D10); // near-black, faint cool tint
  static const bg2 = Color(0xFF0F1216); // surface (tile base)

  // Legacy accent names remapped to the Glyph scheme (keeps screens working):
  static const gold = purple;            // primary accent  -> wand-light
  static const amber = purpleSoft;       // brightest lumen
  static const orange = purpleDeep;      // cool steel (gradient / depth)
  static const cyan = silver;            // secondary accent -> cool silver
  static const violet = Color(0xFFB9C9E8); // cool light variant
  static const pink = Color(0xFFC3D2EC); // alerts -> soft cool (no red)
  static const green = Color(0xFF9FDFC9); // live / connected -> soft cool mint

  static const textHi = Color(0xFFEAEFF6); // moon-white
  static const textMid = Color(0xFF8B939D); // cool silver
  static const textLo = Color(0xFF565D67);  // dim cool grey

  // ---- Market data semantics (trading / scalp / pro screens ONLY) ----
  // Conventional green-up / red-down colours for candles, trend lines, bias,
  // support/resistance, target/stop — kept separate from the purple UI accent
  // so the rest of the app stays monochrome-purple.
  static const up = Color(0xFF2ED47A);   // green  — bullish / up / support / target
  static const down = Color(0xFFF0454B); // red    — bearish / down / resistance / stop

  // Translucent helpers (frosted bento fills / hairline borders on warm black)
  static const glassFill = Color(0x0FFFFFFF);       // ~6% white
  static const glassLine = Color(0x1AFFFFFF);       // ~10% white
  static const glassFillStrong = Color(0x1AFFFFFF); // ~10% white

  // ---- Gradients ----
  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg1, bg0],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purpleSoft, purpleDeep], // warm amber for the primary button / orb
  );

  static const cyanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A241D), Color(0xFF161310)], // warm charcoal (secondary)
  );

  // Subtle top-lit gradient used to make bento tiles look glassy/frosted.
  static const _bentoFill = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x14FFFFFF), Color(0x08FFFFFF)],
  );

  // ---- Bento tile: rounded, frosted, hairline border. `glow` adds an amber
  // aura for the "active/featured" tiles. Token name `glass` kept for
  // backwards compatibility with existing screens. ----
  static BoxDecoration glass({double radius = 22, Color? tint, bool glow = false}) =>
      BoxDecoration(
        gradient: tint == null ? _bentoFill : null,
        color: tint,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glow ? const Color(0x4096BEFF) : glassLine),
        boxShadow: glow
            ? [
                const BoxShadow(
                    color: Color(0x2E96BEFF), blurRadius: 34, spreadRadius: -6),
              ]
            : const [
                BoxShadow(
                    color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 8)),
              ],
      );

  /// Alias with a clearer name for the bento redesign.
  static BoxDecoration bento({double radius = 22, bool glow = false}) =>
      glass(radius: radius, glow: glow);

  static List<BoxShadow> glowShadow(Color c, {double blur = 40, double spread = 0}) =>
      [BoxShadow(color: c, blurRadius: blur, spreadRadius: spread)];

  static List<BoxShadow> glow(Color c, {double blur = 40, double spread = 0}) =>
      [BoxShadow(color: c, blurRadius: blur, spreadRadius: spread)];

  /// Ambient warm corner-glow layer to sit behind a screen's content (put in a
  /// Stack under everything). Mirrors the sample's amber "sunrise" glow.
  static Widget ambientGlow() => IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -130,
              right: -90,
              child: _glowBlob(const Color(0x2696BEFF), 340),
            ),
            Positioned(
              bottom: -150,
              left: -110,
              child: _glowBlob(const Color(0x16586C9A), 360),
            ),
          ],
        ),
      );

  static Widget _glowBlob(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );

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
