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

  // ---- Signature colours (warm amber "bento" theme) ----
  static const purple = Color(0xFFF2A64C);     // primary WARM AMBER accent
  static const purpleSoft = Color(0xFFFFCB8A); // light amber
  static const purpleDeep = Color(0xFFB56420); // deep amber / burnt orange
  static const silver = Color(0xFFCBC6BD);     // warm silver (secondary)
  static const glowOrange = Color(0xFFFF8A3D); // ambient corner glow

  // ---- Core palette (warm near-black canvas) ----
  static const bg0 = Color(0xFF070605); // warm pure black
  static const bg1 = Color(0xFF0E0C0A); // near-black, faint warm tint
  static const bg2 = Color(0xFF17130F); // warm charcoal (bento tile base)

  // Legacy accent names remapped to the amber scheme (keeps screens working):
  static const gold = purple;            // primary accent  -> amber
  static const amber = purpleSoft;       // light amber
  static const orange = purpleDeep;      // deep amber (gradient / glow)
  static const cyan = silver;            // secondary accent -> warm silver
  static const violet = Color(0xFFE59A57); // amber variant
  static const pink = Color(0xFFFFB27A); // alerts -> soft amber (no red)
  static const green = Color(0xFF7BE0A3); // live / connected -> soft mint

  static const textHi = Color(0xFFF4EFE8); // warm white
  static const textMid = Color(0xFFA8A197); // warm silver
  static const textLo = Color(0xFF6A655D);  // dim warm grey

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
        border: Border.all(color: glow ? const Color(0x40F2A64C) : glassLine),
        boxShadow: glow
            ? [
                const BoxShadow(
                    color: Color(0x33F2A64C), blurRadius: 34, spreadRadius: -6),
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
              top: -120,
              right: -80,
              child: _glowBlob(const Color(0x33FF8A3D), 320),
            ),
            Positioned(
              bottom: -140,
              left: -100,
              child: _glowBlob(const Color(0x22B56420), 340),
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
