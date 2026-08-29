// The type scale.
//
// Before this file every widget set its own size inline, and the app had grown
// sixteen distinct ones -- 9.5 through 26 -- with no relation between them,
// plus thirty uses of `fontFamily: 'monospace'` for page numbers, verse keys
// and counts. Both were doing damage. Monospace metadata reads as debug
// output rather than as a book's chrome, and `'monospace'` is not a bundled
// family: it resolves to Roboto Mono on Android, Courier on iOS and something
// else again on the web, so a label tuned on one platform is a different
// width and colour on the next.
//
// So: one face, five roles for the chrome and three for scripture. A widget
// names a role. It does not name a size.
//
// Two rules the scale keeps, both because this app speaks Arabic:
//
//   * No letter-spacing. Tracking pulls joined Arabic letters apart -- what
//     reads as refinement in Latin reads as broken type in Arabic.
//   * No fontWeight above 400. Amiri ships Regular alone here, so anything
//     heavier is synthesised by the engine, and synthetic bold on naskh
//     thickens the joins into blots. Emphasis is carried by size and by ink,
//     which the palette has three grades of: `ink`, `inkSoft`, `inkMute`.

import 'package:flutter/material.dart';

import 'theme.dart';

TextStyle _face(double size, Color color, double height) => TextStyle(
      fontFamily: kUiFace,
      fontSize: size,
      height: height,
      color: color,
    );

// ---------------------------------------------------------------- the chrome

/// The drawer's head, and the one number on a screen that is the point of it.
TextStyle tDisplay([Color? c]) => _face(28, c ?? palette.ink, 1.3);

/// A bar title, a card's heading, the āyah a panel is about.
TextStyle tTitle([Color? c]) => _face(21, c ?? palette.ink, 1.4);

/// Running text: a setting's name, a list row, a sentence of explanation.
TextStyle tBody([Color? c]) => _face(17, c ?? palette.ink, 1.55);

/// The line under a row: where a thing is, what it costs, why it is here.
TextStyle tCaption([Color? c]) => _face(14, c ?? palette.inkSoft, 1.55);

/// Counts, page numbers, verse keys, the small header over a group. This is
/// what every `monospace` in the app used to be.
TextStyle tLabel([Color? c]) => _face(12, c ?? palette.inkMute, 1.4);

// ------------------------------------------------------------- the scripture
//
// Arabic wants about a quarter more size than Latin for the same legibility,
// which is why these start where the chrome stops. The generous leading is
// not taste: naskh hangs marks well above and below the baseline, and at 1.4
// they collide across lines.

/// The wording a screen is asking about -- the road in the drill, the phrase
/// at the head of a panel card.
TextStyle tQuranLead([Color? c]) => _face(23, c ?? palette.ink, 1.95);

/// Scripture in a list or a card body.
TextStyle tQuranBody([Color? c]) => _face(20, c ?? palette.ink, 1.95);

/// Scripture that is reference rather than the point: a sibling's sūrah name,
/// a ḍābiṭ sentence, a run-up dimmed behind the thing being asked.
TextStyle tQuranSmall([Color? c]) => _face(17, c ?? palette.ink, 1.85);
