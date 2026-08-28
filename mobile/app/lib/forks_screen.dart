// The official mutashābihāt, as forks.
//
// A fork is the road every position shares, the point where they part, and each
// way out with the positions taking it. `shape` says what it costs to hold:
// `all_but_one` is one exception to remember, `many` is a peg per position.
//
// This is the port of app/forks_page.py -- the page the web service serves at
// /official, and the one thing in the project the phone could not see.

import 'package:flutter/material.dart';
import 'package:quran_port/forks.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

const Color _ink = Color(0xFF191C19);
const Color _inkSoft = Color(0xFF4A5049);
const Color _inkMute = Color(0xFF767C74);
const Color _accent = Color(0xFF16584A);
const Color _gold = Color(0xFF8A6C22);

/// Cheapest to hold first, which is the order `sort: useful` puts them in.
const Map<String, ({String label, String gloss, Color tint})> kShapeInfo = {
  'all_but_one': (
    label: 'all but one',
    gloss: 'every position takes the same way out except one',
    tint: Color(0xFFE4EFEA),
  ),
  'two_way': (
    label: 'two ways',
    gloss: 'the positions split two ways',
    tint: Color(0xFFFBEFD2),
  ),
  'many': (
    label: 'many ways',
    gloss: 'a peg is needed for each position',
    tint: Color(0xFFF3E4E0),
  ),
  'no_fork': (
    label: 'no fork',
    gloss: 'the positions never part; they are told apart by what precedes',
    tint: Color(0xFFF3F4F0),
  ),
};

class ForksScreen extends StatefulWidget {
  const ForksScreen({super.key, required this.db, required this.onGo});

  final CommonDatabase db;

  /// Turn the muṣḥaf to this page and select this āyah.
  final void Function(int page, String verseKey) onGo;

  @override
  State<ForksScreen> createState() => _ForksScreenState();
}

class _ForksScreenState extends State<ForksScreen> {
  static const int _pageSize = 20;

  String? _shape;
  String _sort = 'useful';
  int _offset = 0;
  Map<String, Object?>? _doc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _doc = forkIndex(
        widget.db,
        shape: _shape,
        sort: _sort,
        limit: _pageSize,
        offset: _offset,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final counts = doc?['counts'] as Map<String, Object?>?;
    final total = (counts?['total'] as int?) ?? 0;
    final phrases =
        ((doc?['phrases'] as List?) ?? const []).cast<Map<String, Object?>>();

    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFA),
      appBar: AppBar(
        title: const Text('Forks'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(84),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _chip('all', _shape == null, () {
                      _shape = null;
                      _offset = 0;
                      _load();
                    }),
                    for (final s in kShapeInfo.keys)
                      _chip(kShapeInfo[s]!.label, _shape == s, () {
                        _shape = s;
                        _offset = 0;
                        _load();
                      }),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Text('$total forks',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: _inkMute)),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _sort,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(fontSize: 12, color: _ink),
                      items: const [
                        DropdownMenuItem(value: 'useful', child: Text('useful')),
                        DropdownMenuItem(
                            value: 'positions', child: Text('positions')),
                        DropdownMenuItem(
                            value: 'branches', child: Text('branches')),
                        DropdownMenuItem(value: 'surahs', child: Text('sūrahs')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        _sort = v;
                        _offset = 0;
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: doc == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: phrases.length + 1,
              itemBuilder: (context, i) {
                if (i == phrases.length) return _pager(total);
                return _ForkCard(
                  fork: phrases[i],
                  db: widget.db,
                  onGo: widget.onGo,
                );
              },
            ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: on,
          onSelected: (_) => tap(),
        ),
      );

  Widget _pager(int total) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _offset <= 0
                  ? null
                  : () {
                      _offset = (_offset - _pageSize).clamp(0, 1 << 30);
                      _load();
                    },
              child: const Text('previous'),
            ),
            Text('${_offset + 1}–${(_offset + _pageSize).clamp(0, total)}',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11, color: _inkMute)),
            TextButton(
              onPressed: _offset + _pageSize >= total
                  ? null
                  : () {
                      _offset += _pageSize;
                      _load();
                    },
              child: const Text('next'),
            ),
          ],
        ),
      );
}

class _ForkCard extends StatelessWidget {
  const _ForkCard({required this.fork, required this.db, required this.onGo});

  final Map<String, Object?> fork;
  final CommonDatabase db;
  final void Function(int page, String verseKey) onGo;

  @override
  Widget build(BuildContext context) {
    final shape = fork['shape'] as String;
    final info = kShapeInfo[shape];
    final branches =
        (fork['branches'] as List).cast<Map<String, Object?>>();
    final tail = fork['road_tail_ar'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEEE9)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: info?.tint ?? const Color(0xFFF3F4F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(info?.label ?? shape,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _gold)),
              ),
              const Spacer(),
              Text(
                '${fork['position_count']} places  ·  '
                '${fork['branch_count']} ways  ·  '
                '${fork['surah_count']} sūrahs',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 10, color: _inkMute),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // The road: the shared wording, then whatever the positions still say
          // together after it, dimmed to show where the agreement runs on.
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: fork['phrase_ar'] as String,
                style: const TextStyle(
                    fontFamily: 'Amiri', fontSize: 20, height: 1.9, color: _ink),
              ),
              if (tail != null)
                TextSpan(
                  text: ' $tail',
                  style: const TextStyle(
                      fontFamily: 'Amiri',
                      fontSize: 20,
                      height: 1.9,
                      color: _inkMute),
                ),
            ]),
            textDirection: TextDirection.rtl,
          ),

          if (info != null) ...[
            const SizedBox(height: 6),
            Text(info.gloss,
                style: const TextStyle(fontSize: 11, color: _inkMute)),
          ],
          const Divider(height: 20),

          // Each way out of the fork.
          for (final b in branches) _Branch(branch: b, onGo: onGo),
        ],
      ),
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({required this.branch, required this.onGo});

  final Map<String, Object?> branch;
  final void Function(int page, String verseKey) onGo;

  @override
  Widget build(BuildContext context) {
    final positions =
        (branch['positions'] as List).cast<Map<String, Object?>>();
    final largest = branch['is_largest'] == true;
    final token = branch['token_ar'] as String?;
    final endsSurah = branch['ends_surah'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(largest ? Icons.subdirectory_arrow_left : Icons.arrow_right,
                  size: 16, color: largest ? _inkMute : _accent),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  endsSurah ? '— ends the sūrah —' : (token ?? '—'),
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 17,
                    color: largest ? _inkSoft : _ink,
                    fontWeight: largest ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${branch['position_count']}',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11, color: _inkMute)),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final p in positions)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(
                    '${p['surah_name_ar']} ${p['verse_key']}',
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: p['page'] == null
                      ? null
                      : () => onGo(p['page'] as int, p['verse_key'] as String),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
