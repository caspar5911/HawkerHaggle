// Full sweep of the on-phone game, no AI: every stall x item x play style, many times, checking the rules on
// every reply. Port of server/tests/test_sweep.py.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

const eventsAll = {
  'greet', 'counter', 'final', 'insulted', 'accept', 'flattered', 'flattery_tired', 'competitor_drop',
  'competitor_annoyed', 'bulk', 'regular', 'smalltalk', 'rude', 'callback', 'letgo', 'refuse', 'confused', 'plead',
  'plead_no', 'clarify', 'confirm', 'unsure', 'budget_best', 'pity', 'pity_tired', 'deflect', //
};

const typed = [
  '15 can?', r'$12 lah', 'ok lah', 'can cheaper?', 'wah so nice', 'next stall cheaper leh', 'I buy two',
  'I come every week', "how's your day", 'stupid', 'never mind', 'deal', 'I buy 100 for 150?', 'hmm ok', '😂😂',
  'asdfgh', '3 for 20?', 'ok lah but my wallet crying', 'my budget only 10', r'I only have $9', r'I only have $16',
  "I'm starving, nothing to eat", 'no money lah', '12 can?', '12 can?', r'$2 less can?', 'meet halfway lah',
  'round down lah', '2 for 30?', 'wah so nice, 14 can?', 'go on a date with me', '15', //
];

const styles = [
  'bold', 'safe', 'tactic', 'random_tap', 'typed', 'old_app_accept_spam', 'cancel_reoffer', 'button_buy',
  'sweet_talk_then_budget', 'flatter_and_offer', 'walk', //
];

final dollarNoNumber = RegExp(r'\$(?!\d)');

void check(Map g, Set<String> seen) {
  seen.add(g['event'] as String);
  expect(eventsAll, contains(g['event']));
  final text = jsonEncode(g);
  expect(text.contains('"floor"') || text.contains('"fair"'), isFalse);
  final line = g['line'] as String;
  expect(line.isNotEmpty && !line.contains('{') && !line.contains('}'), isTrue, reason: line);
  expect(dollarNoNumber.hasMatch(line), isFalse, reason: line);
  final shouldBeEmpty = g['done'] == true || g['pending'] != null;
  expect((g['suggestions'] as List).isEmpty, shouldBeEmpty, reason: '${g['event']} ${g['pending']}');
  if (g['pending'] != null) {
    expect(['confirm', 'clarify'], contains(g['event']));
    expect(g['done'], isFalse);
  }
}

Future<(Map, int)> play(Game game, Map stall, Map item, String style, math.Random rnd, Set<String> seen) async {
  final floor = (item['floor'] as num).toDouble();
  var g = await game.start(stall['id'] as String, item['id'] as String);
  check(g, seen);
  var lastAsk = (g['ask'] as num).toDouble();
  var wasPending = false;
  for (var n = 0; n < 80; n++) {
    if (g['done'] == true) {
      await expectLater(game.move(g['id'] as String, pick: 0), throwsA(isA<GameError>()));
      return (g, n);
    }
    final pending = g['pending'] != null;
    final ask = (g['ask'] as num).toDouble();
    Map<String, Object?> body;
    switch (style) {
      case 'bold' || 'safe' || 'tactic':
        body = pending
            ? {'move': 'confirm'}
            : {
                'pick': ['bold', 'safe', 'tactic'].indexOf(style),
              };
      case 'random_tap':
        body = pending
            ? ([
                {'move': 'confirm'},
                {'move': 'cancel'},
              ])[rnd.nextInt(2)]
            : ([
                {'pick': 0},
                {'pick': 1},
                {'pick': 2},
                {'move': 'accept'},
                {'move': 'walk'},
              ])[rnd.nextInt(5)];
      case 'typed':
        final pool = [
          ...typed,
          if (pending) ...['ok lah', 'yes', 'hmm'],
        ];
        body = {'text': pool[rnd.nextInt(pool.length)]};
      case 'old_app_accept_spam':
        body = {'move': 'accept'};
      case 'cancel_reoffer':
        body = pending ? {'move': 'cancel'} : {'pick': 1};
      case 'button_buy':
        body = pending
            ? {'move': 'confirm'}
            : ([
                {'pick': 0},
                {'pick': 1},
                {'move': 'buy'},
              ])[rnd.nextInt(3)];
      case 'sweet_talk_then_budget':
        body = pending
            ? {'move': 'confirm'}
            : {'text': n < 4 ? 'wah so nice' : 'I only have \$${math.max(1, (ask * 0.6).floor())}'};
      case 'flatter_and_offer':
        body = pending ? {'move': 'confirm'} : {'text': 'wah so nice, ${math.max(1, ask.floor() - 1)} can?'};
      case 'walk':
        body = pending ? {'move': 'confirm'} : {'move': 'walk'};
      default:
        throw ArgumentError(style);
    }
    g = await game.move(
      g['id'] as String,
      pick: body['pick'] as int?,
      move: body['move'] as String?,
      text: body['text'] as String?,
    );
    check(g, seen);
    final nowAsk = (g['ask'] as num).toDouble();
    expect(nowAsk <= lastAsk + 1e-9, isTrue, reason: '$style: price went up $lastAsk -> $nowAsk');
    lastAsk = nowAsk;
    if (g['done'] == true && g['result'] == 'deal') {
      expect(wasPending || body['move'] == 'buy', isTrue, reason: '$style: deal without a yes ($body)');
      expect((g['deal'] as num) >= floor * 0.9 - 0.01, isTrue, reason: '$style: below floor ${g['deal']}');
      expect([1, 2, 3], contains(g['stars']));
    }
    wasPending = g['pending'] != null;
  }
  if (!['typed', 'cancel_reoffer'].contains(style)) {
    fail('$style on ${stall['id']}/${item['id']} did not end in 80 moves');
  }
  return (g, 80);
}

void main() {
  test('sweep every stall, item and play style (no AI)', () async {
    final game = Game(content: content, store: MemoryKeyValue(), random: math.Random(1));
    await game.load();
    final rnd = math.Random(2026);
    final seen = <String>{};
    final results = <String, int>{};
    for (final s in content['stalls'] as List) {
      for (final it in (s as Map)['items'] as List) {
        for (final style in styles) {
          for (var i = 0; i < 12; i++) {
            final (g, _) = await play(game, s, it as Map, style, rnd, seen);
            final key = '$style/${g['result'] == '' ? 'unfinished' : g['result']}';
            results[key] = (results[key] ?? 0) + 1;
          }
        }
      }
    }
    expect(results['old_app_accept_spam/deal'], 8 * 12); // never stuck
    int count(String r) => results.entries.where((e) => e.key.endsWith('/$r')).fold(0, (a, e) => a + e.value);
    expect(count('deal'), greaterThan(100));
    expect(count('walked'), greaterThan(10));
    expect(count('refused'), greaterThan(10));
    expect(eventsAll.difference(seen), anyOf(isEmpty, equals({'confused'}))); // confused needs the AI
    final me = game.me();
    expect(me['haggles'], 500); // finished haggles are kept on the phone (the last 500)
  });

  test('every event has lines for every stall and they fill in', () {
    for (final s in content['stalls'] as List) {
      final lines = (s as Map)['lines'] as Map;
      for (final ev in eventsAll) {
        expect(lines[ev], isA<List>(), reason: '${s['id']} has no lines for $ev');
        for (final l in lines[ev] as List) {
          final out = '$l'.replaceAll('{item}', 'durian').replaceAll('{price}', r'$12').replaceAll('{offer}', r'$9');
          expect(out.contains('{') || out.contains('}'), isFalse);
        }
      }
    }
  });

  test('asking back never changes the haggle', () async {
    final game = Game(content: content, store: MemoryKeyValue());
    await game.load();
    final g = await game.start('lim', 'prawns');
    for (var i = 0; i < 25; i++) {
      final r = await game.move(g['id'] as String, text: 'ok lah');
      expect(r['event'], 'clarify');
      expect(r['ask'], g['ask']);
      expect(r['patience'], g['patience']);
    }
  });
}
