// The Dart game core must give the same answers as the Python reference (server/hh).
// Regenerate the reference with: server/.venv/bin/python tools/export_fixtures.py
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/engine.dart';
import 'package:hawker_haggle/core/py.dart';
import 'package:hawker_haggle/core/reader.dart';
import 'package:hawker_haggle/core/voice.dart';

final ref = jsonDecode(File('test/fixtures/reference.json').readAsStringSync()) as Map<String, dynamic>;
final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

double? d(Object? v) => v == null ? null : (v as num).toDouble();

void same(Object? got, Object? want, String what) {
  if (want is num && got is num) {
    expect((got - want).abs() < 1e-9, isTrue, reason: '$what: got $got, want $want');
  } else {
    expect(got, want, reason: what);
  }
}

void main() {
  test('rounding', () {
    for (final r in ref['nice'] as List) {
      same(nice(d(r[0])!), r[1], 'nice(${r[0]})');
    }
    for (final r in ref['nice_up'] as List) {
      same(niceUp(d(r[0])!), r[1], 'nice_up(${r[0]})');
    }
    for (final r in ref['money'] as List) {
      same(money(d(r[0])), r[1], 'money(${r[0]})');
    }
  });

  test('word rules, fast path, plain yes', () {
    for (final r in ref['rules'] as List) {
      final (move, price) = rules(r[0] as String);
      same(move, r[1][0], 'rules(${r[0]}).move');
      same(price, d(r[1][1]), 'rules(${r[0]}).price');
    }
    for (final r in ref['heard_by_rules'] as List) {
      final got = heardByRules(r[0] as String).toMap();
      final want = r[1] as Map;
      for (final k in want.keys) {
        same(
          got[k],
          want[k] is num ? d(want[k]) : want[k] ?? (k == 'also' || k == 'rel_op' || k == 'per' ? '' : null),
          'heard_by_rules(${r[0]}).$k',
        );
      }
    }
    for (final r in ref['plain_yes'] as List) {
      same(plainYes(r[0] as String), r[1], 'plain_yes(${r[0]})');
    }
    for (final r in ref['fast_offer'] as List) {
      same(fastOffer(r[0] as String, d(r[1])!), d(r[2]), 'fast_offer(${r[0]}, ${r[1]})');
    }
  });

  test('price-safety check, mood, openers, transcript', () {
    for (final r in ref['checked'] as List) {
      final got = checked(
        r[0] as String,
        [for (final a in r[1] as List) a as num],
        counts: [for (final c in r[2] as List) c as num],
        dollarCounts: r[3] as bool,
      );
      same(got, r[4], 'checked(${(r[0] as String).length > 40 ? '${(r[0] as String).substring(0, 40)}…' : r[0]})');
    }
    for (final r in ref['without_thinking'] as List) {
      same(withoutThinking(r[0] as String), r[1], 'without_thinking(${r[0]})');
    }
    for (final r in ref['mood_line'] as List) {
      same(moodLine(r[0] as String, d(r[1]), r[2] as String), r[3], 'mood_line(${r.take(3).toList()})');
    }
    for (final r in ref['opener_hint'] as List) {
      same(openerHint([for (final m in r[0] as List) m as Map]), r[1], 'opener_hint(${(r[0] as List).length})');
    }
    for (final r in ref['transcript'] as List) {
      same(transcript([for (final m in r[0] as List) m as Map], r[1] as String), r[2], 'transcript');
    }
  });

  test('engine: same outcome and state after every move', () {
    final stalls = {for (final s in content['stalls'] as List) (s as Map)['id']: s};
    var moves = 0;
    for (final t in ref['engine'] as List) {
      final st = stalls[t['stall']] as Map;
      final it = (st['items'] as List).firstWhere((i) => (i as Map)['id'] == t['item']) as Map;
      final h = Haggle(Item.fromJson(it), Personality.fromJson(st['personality'] as Map));
      for (final step in t['steps'] as List) {
        final kind = step['kind'] as String;
        final where = '${t['stall']}/${t['item']} move ${++moves} $kind ${step['price']}';
        if (kind.startsWith('side:')) {
          h.side(kind.substring(5));
        } else {
          final o = h.move(kind, d(step['price'])).toJson();
          for (final e in (step['out'] as Map).entries) {
            same(o[e.key], e.value is num ? d(e.value) : e.value, '$where out.${e.key}');
          }
        }
        final s = h.s.toJson();
        for (final e in (step['state'] as Map).entries) {
          same(s[e.key], e.value is num ? d(e.value) : e.value, '$where state.${e.key}');
        }
        same(h.floorNow(), d(step['floor_now']), '$where floor_now');
        same(h.stars(), step['stars'], '$where stars');
        final sug = h.suggestions();
        same(sug.length, step['n_suggest'], '$where suggestions');
        for (var i = 0; i < (step['suggest'] as List).length; i++) {
          same(sug[i]['move'], step['suggest'][i][0], '$where suggestion $i');
          same(sug[i]['price'], d(step['suggest'][i][1]), '$where suggestion $i price');
        }
      }
    }
    expect(moves, greaterThan(1000));
  });

  test('python helpers', () {
    expect(roundHalfEven(26.5), 26);
    expect(roundHalfEven(27.5), 28);
    expect(pyRound(0.125, 2), 0.12);
    expect(pySlice('😂😂😂', 2), '😂😂');
    expect(pyRe(r'\bdeal\b').hasMatch('便宜deal'), isFalse); // like Python: Chinese letters are word characters
  });
}
