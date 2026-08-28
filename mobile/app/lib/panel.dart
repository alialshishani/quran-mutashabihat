// What the print cannot say.
//
// For the tapped ayah: every official mutashabih phrase touching it, and for
// each, the peg that tells this position from the others -- then every sibling
// position, each with its own peg, as a way to turn there.
//
// Every string here comes from the database. The peg sentences are `pegs.text_ar`
// as `pipeline.pegs` wrote them; nothing is composed in the app.

import 'package:flutter/material.dart';
import 'theme.dart';

// The palette in force, read by name; see theme.dart. These are getters
// rather than constants because the light can change while the app is up.
Color get _raised => palette.raised;
Color get _paper => palette.paper;
Color get _ink => palette.ink;
Color get _inkSoft => palette.inkSoft;
Color get _inkMute => palette.inkMute;
Color get _accent => palette.accent;
Color get _gold => palette.gold;
Color get _goldBright => palette.goldBright;
Color get _goldSoft => palette.goldSoft;
Color get _goldDeep => palette.goldDeep;
Color get _surface => palette.surface;
Color get _surfaceAlt => palette.surfaceAlt;
Color get _rule => palette.line;

class MutashabihatPanel extends StatelessWidget {
  const MutashabihatPanel({
    super.key,
    required this.verseKey,
    required this.matches,
    required this.detected,
    required this.onJump,
  });

  final String verseKey;

  /// The curated QUL list, each position with its peg.
  final List<Map<String, Object?>> matches;

  /// Pass A's own detection: spans this ayah repeats elsewhere, with any dabit
  /// that verified for them. Behind a disclosure, as the web page has it -- the
  /// curated phrases are the answer, these are the evidence behind it.
  final List<Map<String, Object?>> detected;

  /// (page, verseKey) of the sibling to turn to.
  final void Function(int page, String verseKey) onJump;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => DecoratedBox(
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(verseKey,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: _inkMute)),
                const SizedBox(width: 10),
                Text(
                  matches.isEmpty
                      ? 'no official mutashābihāt'
                      : '${matches.length} official '
                          '${matches.length == 1 ? "phrase" : "phrases"}',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500, color: _ink),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  detected.isEmpty
                      ? 'This āyah carries no phrase from the curated list, '
                          'and nothing repeated was detected in it.'
                      : 'No phrase from the curated list. What pass A detected '
                          'is below.',
                  style: TextStyle(fontSize: 13, color: _inkSoft, height: 1.5),
                ),
              ),
            for (final m in matches) _Phrase(match: m, onJump: onJump),
            if (detected.isNotEmpty)
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${detected.length} detected '
                    '${detected.length == 1 ? "repeat" : "repeats"}',
                    style: TextStyle(fontSize: 13, color: _accent),
                  ),
                  subtitle: Text(
                    "this project's own pass-A detection, not the curated list",
                    style: TextStyle(fontSize: 11, color: _inkMute),
                  ),
                  children: [
                    for (final d in detected)
                      _Detected(match: d, onJump: onJump),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Phrase extends StatelessWidget {
  const _Phrase({required this.match, required this.onJump});

  final Map<String, Object?> match;
  final void Function(int page, String verseKey) onJump;

  @override
  Widget build(BuildContext context) {
    final here = (match['here'] as List).cast<Map<String, Object?>>();
    final elsewhere = (match['elsewhere'] as List).cast<Map<String, Object?>>();

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: _raised,
        border: Border.all(color: _surfaceAlt),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The shared wording itself.
          Text(
            match['text_ar'] as String,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontFamily: 'Amiri', fontSize: 21, height: 1.9, color: _ink),
          ),
          const SizedBox(height: 8),
          Text(
            '${match['set_count']} places  ·  '
            '${match['surah_count']} sūrahs  ·  '
            '${match['span_len']} words',
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 11, color: _inkMute),
          ),
          const Divider(height: 22),

          // The peg for the position sitting in the āyah that was tapped.
          for (final h in here) _Peg(position: h, isHere: true),

          if (elsewhere.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
                'the other ${elsewhere.length} '
                '${elsewhere.length == 1 ? "place" : "places"}',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: _inkMute,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final e in elsewhere) _Sibling(position: e, onJump: onJump),
          ],
        ],
      ),
    );
  }
}

class _Peg extends StatelessWidget {
  const _Peg({required this.position, required this.isHere});

  final Map<String, Object?> position;
  final bool isHere;

  @override
  Widget build(BuildContext context) {
    final peg = position['peg'] as Map<String, Object?>?;
    if (peg == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('no ḍābiṭ verified for this position',
            style: TextStyle(fontSize: 12, color: _inkMute)),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHere ? _goldSoft : _surface,
        borderRadius: BorderRadius.circular(6),
        border: isHere ? Border.all(color: _goldBright, width: 0.8) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(peg['kind'] as String,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      color: _gold,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('strength ${peg['strength']}',
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 9.5, color: _inkMute)),
            ],
          ),
          const SizedBox(height: 6),
          // pegs.text_ar, exactly as pipeline.pegs wrote it.
          Text(
            peg['text_ar'] as String,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: 'Amiri',
              fontSize: isHere ? 16 : 14,
              height: 1.85,
              color: isHere ? _goldDeep : _inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sibling extends StatelessWidget {
  const _Sibling({required this.position, required this.onJump});

  final Map<String, Object?> position;
  final void Function(int page, String verseKey) onJump;

  @override
  Widget build(BuildContext context) {
    final page = position['page'] as int?;
    final key = position['verse_key'] as String;

    return InkWell(
      onTap: page == null ? null : () => onJump(page, key),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(position['surah_name_ar'] as String,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontFamily: 'Amiri', fontSize: 15, color: _ink)),
                const SizedBox(width: 8),
                Text(key,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: _inkMute)),
                const Spacer(),
                if (page != null)
                  Text('page $page  ›',
                      style: TextStyle(
                          fontSize: 11,
                          color: _accent,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            _Peg(position: position, isHere: false),
          ],
        ),
      ),
    );
  }
}

/// One span pass A found repeating, with its dawabit.
class _Detected extends StatelessWidget {
  const _Detected({required this.match, required this.onJump});

  final Map<String, Object?> match;
  final void Function(int page, String verseKey) onJump;

  @override
  Widget build(BuildContext context) {
    final elsewhere = (match['elsewhere'] as List).cast<Map<String, Object?>>();
    final dawabit = (match['dawabit'] as List).cast<Map<String, Object?>>();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            match['span_text'] as String,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontFamily: 'Amiri', fontSize: 18, height: 1.85, color: _ink),
          ),
          const SizedBox(height: 6),
          Text(
            '${match['occurrence_count']} occurrences  \u00b7  '
            '${match['span_len']} words'
            '${match['cross_surah'] == true ? "  \u00b7  crosses a surah" : ""}',
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 10, color: _inkMute),
          ),
          for (final d in dawabit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(d['rule_code'] as String,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9.5,
                              letterSpacing: 0.8,
                              color: _gold,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      if (d['verified'] == true)
                        Icon(Icons.check, size: 12, color: _accent),
                      const Spacer(),
                      Text('strength ${d['strength']}',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9.5,
                              color: _inkMute)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // dawabit.text_ar, as pipeline.apply_rules wrote it.
                  Text(
                    d['text_ar'] as String,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 15,
                        height: 1.8,
                        color: _inkSoft),
                  ),
                ],
              ),
            ),
          if (elsewhere.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final p in elsewhere)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text('${p['surah_name_ar']} ${p['verse_key']}',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 11)),
                    onPressed: p['page'] == null
                        ? null
                        : () =>
                            onJump(p['page'] as int, p['verse_key'] as String),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
