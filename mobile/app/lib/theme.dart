// The two lights the muṣḥaf is read by.
//
// One palette, named for what the colours are for rather than what they are:
// `paper` and `ink`, not `white` and `black`. The dark set is the same page
// under a lamp, not an inverted image -- an inversion would turn the gold of
// the āyah markers blue, and the gold is the one colour on the page that is
// not the printer's ink.
//
// The names are read through a top-level `palette`, set once per build by the
// root from the mode in force. That is why so little of the app mentions a
// colour twice: a widget asks for `_ink` and gets the ink of whichever light
// is on.

import 'package:flutter/material.dart';

/// Which light to read by. `system` follows the platform, which is what a
/// reader who sets their phone to dark at maghrib actually wants.
enum ThemeChoice { light, dark, system }

ThemeChoice themeChoiceFrom(String? name) => switch (name) {
      'light' => ThemeChoice.light,
      'dark' => ThemeChoice.dark,
      _ => ThemeChoice.system,
    };

class Palette {
  const Palette({
    required this.dark,
    required this.paper,
    required this.card,
    required this.ink,
    required this.inkSoft,
    required this.inkMute,
    required this.accent,
    required this.accentSoft,
    required this.gold,
    required this.goldBright,
    required this.goldSoft,
    required this.goldDeep,
    required this.raised,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.wrong,
    required this.wrongSoft,
    required this.wrongSofter,
    required this.shadow,
    required this.selection,
    required this.covered,
  });

  final bool dark;

  /// The sheet, and everything behind it.
  final Color paper;

  /// The chrome laid on the sheet: near the paper, not of it.
  final Color card;

  final Color ink;
  final Color inkSoft;
  final Color inkMute;

  final Color accent;
  final Color accentSoft;

  /// The āyah markers and the rules the muṣḥaf draws in gold.
  final Color gold;

  /// The brighter gold that marks a mutashābih phrase under the line.
  final Color goldBright;
  final Color goldSoft;
  final Color goldDeep;

  /// A card lifted off the paper: lighter than the page in the day, lighter
  /// than the page at night too. It has to read as nearer, not as darker.
  final Color raised;

  final Color surface;
  final Color surfaceAlt;
  final Color line;

  final Color wrong;
  final Color wrongSoft;
  final Color wrongSofter;

  final Color shadow;

  /// Behind the selected āyah.
  final Color selection;

  /// Behind a word recall is holding back. It stands for words, so it has to
  /// read as a band of something withheld and not as an empty line.
  final Color covered;
}

const Palette kLight = Palette(
  dark: false,
  paper: Color(0xFFFCFCFA),
  card: Color(0xF5FFFFFF),
  ink: Color(0xFF191C19),
  inkSoft: Color(0xFF4A5049),
  inkMute: Color(0xFF767C74),
  accent: Color(0xFF16584A),
  accentSoft: Color(0xFFE4EFEA),
  gold: Color(0xFF8A6C22),
  goldBright: Color(0xFFD8A93C),
  goldSoft: Color(0xFFFBEFD2),
  goldDeep: Color(0xFF6B4708),
  raised: Color(0xFFFFFFFF),
  surface: Color(0xFFF3F4F0),
  surfaceAlt: Color(0xFFECEEE9),
  line: Color(0xFFDFE2DC),
  wrong: Color(0xFF8C3B2E),
  wrongSoft: Color(0xFFF7E7E4),
  wrongSofter: Color(0xFFF3E4E0),
  shadow: Color(0x22000000),
  selection: Color(0x33D8A93C),
  covered: Color(0x0F191C19),
);

// Warm, not blue: the paper it stands for is warm, and a cold grey under Arabic
// type reads as a screen rather than as a page.
const Palette kDark = Palette(
  dark: true,
  paper: Color(0xFF16150F),
  card: Color(0xF5262420),
  ink: Color(0xFFEAE7DE),
  inkSoft: Color(0xFFB6B2A7),
  inkMute: Color(0xFF8B877E),
  accent: Color(0xFF5FC2A6),
  accentSoft: Color(0xFF1D3A33),
  gold: Color(0xFFC9A24A),
  goldBright: Color(0xFFE0B75A),
  goldSoft: Color(0xFF2C2517),
  goldDeep: Color(0xFFE9D091),
  raised: Color(0xFF242118),
  surface: Color(0xFF201E19),
  surfaceAlt: Color(0xFF272520),
  line: Color(0xFF37342C),
  wrong: Color(0xFFE0907F),
  wrongSoft: Color(0xFF3A241F),
  wrongSofter: Color(0xFF432A23),
  shadow: Color(0x66000000),
  // Lighter than the day's band. On dark paper a gold wash at the same alpha
  // reads as a slab laid over the line rather than as the line marked.
  selection: Color(0x2ED8A93C),
  covered: Color(0x14EAE7DE),
);

/// The palette in force. Set by the root before the app is built, so every
/// widget below can name a colour without threading a theme through.
Palette palette = kLight;

/// The Material theme for a palette: the parts of the app that are ordinary
/// widgets -- bars, tiles, switches, sheets -- rather than the muṣḥaf itself.
ThemeData themeFor(Palette c) {
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: c.dark ? Brightness.dark : Brightness.light,
    surface: c.paper,
    primary: c.accent,
    onSurface: c.ink,
    error: c.wrong,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.paper,
    dividerColor: c.line,
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accentSoft,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: c.paper),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(iconColor: c.inkSoft, textColor: c.ink),
    // Material inverts the snack bar -- dark on light, light on dark -- which
    // at night lays a white slab across the page you are reciting from. It is
    // a card lifted off the page like any other here, so it is coloured as one.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.raised,
      contentTextStyle: TextStyle(color: c.ink, fontSize: 14),
      actionTextColor: c.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.line),
      ),
    ),
    textTheme: c.dark
        ? Typography.material2021(platform: TargetPlatform.android).white
        : Typography.material2021(platform: TargetPlatform.android).black,
  );
}
