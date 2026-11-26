// Legendary items, tag-team combos in co-op, and the daily reminder plan.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/legendary.dart';
import 'package:hawker_haggle/core/progress.dart' show dayKey;
import 'package:hawker_haggle/reminder.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

/// The first day from 1 Dec 2026 with a legendary item at [stall] (or any stall).
DateTime legendDay([String? stall]) {
  for (var d = DateTime(2026, 12, 1, 10); ; d = d.add(const Duration(days: 1))) {
    final l = legendaryOn(dayKey(d));
    if (l != null && (stall == null || l.$1 == stall)) return d;
  }
}

DateTime ordinaryDay() {
  for (var d = DateTime(2026, 12, 1, 10); ; d = d.add(const Duration(days: 1))) {
    if (legendaryOn(dayKey(d)) == null) return d;
  }
}

Future<Game> newGame(DateTime day, {bool unlockAll = false, int seed = 9}) async {
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    random: math.Random(seed),
    unlockAll: unlockAll,
    surprises: false,
    now: () => day,
  );
  await g.load();
  return g;
}

/// Haggles with taps only, like a sensible player: the safer suggested offer until she's firm or losing patience,
/// then OK lah at her price, and yes to the deal.
Future<Map> tapThrough(Game g, Map r) async {
  final id = r['id'] as String;
  for (var i = 0; i < 40 && r['done'] != true; i++) {
    if (r['pending'] != null) {
      r = await g.move(id, move: 'confirm');
    } else if (const ['final', 'budget_best'].contains(r['event']) || (r['patience'] as num) < 35) {
      r = await g.move(id, move: 'accept'); // OK lah, at her price (then confirm)
    } else {
      final sug = (r['suggestions'] as List).cast<Map>();
      final pick = sug.lastIndexWhere((s) => s['move'] == 'offer'); // the safer offer
      r = await g.move(id, pick: pick < 0 ? 0 : pick);
    }
  }
  return r;
}

void main() {
  group('✨ legendary items', () {
    test('about one day in four, the same stall and item for everyone, for every stall now and then', () {
      var legendDays = 0;
      final seen = <String>{};
      for (var d = DateTime(2027, 1, 1); d.year == 2027; d = d.add(const Duration(days: 1))) {
        final l = legendaryOn(dayKey(d));
        if (l == null) continue;
        legendDays++;
        seen.add(l.$1);
        expect(l.$2['id'], 'legend_${l.$1}');
        expect(legendaryOn(dayKey(d)), l); // the same, whoever asks
      }
      expect(legendDays, inInclusiveRange(60, 125));
      expect(seen, legendaryItems.keys.toSet());
      for (final l in legendaryItems.values) {
        final ask = (l['ask'] as num), floor = (l['floor'] as num), fair = (l['fair'] as num);
        expect(floor < fair && fair < ask, isTrue, reason: '${l['id']}');
        expect(floor / ask, greaterThan(0.62), reason: '${l['id']} has less room to bargain than usual');
      }
    });

    test('it shows at its stall and on top of the market, opens even at a locked stall, and is harder', () async {
      final day = legendDay('wong'); // Uncle Wong opens on day 7: locked for a new player
      final g = await newGame(day);
      final s = g.stalls();
      final l = s['legendary'] as Map;
      expect(l['stall'], 'wong');
      expect(l['name'], legendaryItems['wong']!['name']);
      final wong = (s['stalls'] as List).cast<Map>().firstWhere((x) => x['id'] == 'wong');
      expect(wong['locked'], isTrue);
      expect((wong['items'] as List).cast<Map>().last['legendary'], isTrue);
      final r = await g.start('wong', 'legend_wong', 'rain');
      expect(r['legendary'], isTrue);
      expect(r['surprise'], ''); // no market surprise on a legendary haggle
      expect(r['patience'], 75);
      expect(r['ask'], legendaryItems['wong']!['ask']);
    });

    for (final stall in legendaryItems.keys) {
      test('$stall: winnable with taps only; then sold out, in the history, with its sticker', () async {
        final g = await newGame(legendDay(stall), unlockAll: true, seed: stall.length);
        final r = await tapThrough(g, await g.start(stall, 'legend_$stall'));
        expect(r['result'], 'deal', reason: 'taps only should reach a deal for $stall');
        expect(r['new_stickers'], contains('legend'));
        expect((r['notes'] as List).join(' '), contains('legendary'));
        expect(((g.stalls()['legendary'] as Map)['sold_out']), isTrue);
        await expectLater(g.start(stall, 'legend_$stall'), throwsA(isA<GameError>()));
        final h = g.history().first;
        expect(h['item_name'], legendaryItems[stall]!['name']);
        expect(h['emoji'], legendaryItems[stall]!['emoji']);
      });
    }

    test('not on an ordinary day: no banner, and the item cannot be started', () async {
      final g = await newGame(ordinaryDay(), unlockAll: true);
      expect(g.stalls()['legendary'], isNull);
      expect(
        ((g.stalls()['stalls'] as List).cast<Map>())
            .expand((s) => s['items'] as List)
            .cast<Map>()
            .where((i) => i['legendary'] == true),
        isEmpty,
      );
      await expectLater(g.start('mei', 'legend_mei'), throwsA(isA<GameError>()));
    });
  });

  group('🤜🤛 tag-team combos', () {
    Future<(Game, String)> haggle() async {
      final g = await newGame(ordinaryDay(), unlockAll: true);
      final r = await g.start('mei', 'mango', 'none');
      return (g, r['id'] as String);
    }

    test('one friend sweet-talks, the other offers: a combo (warmer, a sticker), at most two', () async {
      final (g, id) = await haggle();
      var r = await g.move(id, text: 'wah auntie your mangoes look so nice!');
      expect(r['combo'], isFalse);
      final mood = (r['mood'] as num).toDouble();
      r = await g.move(id, text: '\$12 can?', friend: 'Melody');
      expect(r['combo'], isTrue);
      expect(r['combos'], 1);
      expect((r['mood'] as num).toDouble(), greaterThan(mood)); // the teamwork charmed her
      expect(g.stickers().firstWhere((s) => s['id'] == 'combo')['earned'], isNotNull);
      // the other way round: the friend sweet-talks, the host offers
      r = await g.move(id, text: 'auntie you eat already?', friend: 'Melody');
      r = await g.move(id, text: '\$13 can?');
      expect(r['combo'], isTrue);
      expect(r['combos'], 2);
      // a third: no more
      await g.move(id, text: 'so nice your stall!', friend: 'Melody');
      r = await g.move(id, text: '\$13.50 can?');
      expect(r['combo'], isFalse);
      expect(r['combos'], 2);
    });

    test("the friend's phone gets the Tag team sticker too", () async {
      final friend = await newGame(ordinaryDay());
      await friend.coopFinish(
        stall: 'mei',
        item: 'mango',
        view: {'result': 'deal', 'deal': 14, 'opening': 18, 'stars': 2, 'combos': 1},
        host: 'Arella',
      );
      expect(friend.stickers().firstWhere((s) => s['id'] == 'combo')['earned'], isNotNull);
      final other = await newGame(ordinaryDay());
      await other.coopFinish(stall: 'mei', item: 'mango', view: {'result': 'deal', 'deal': 14, 'opening': 18});
      expect(other.stickers().firstWhere((s) => s['id'] == 'combo')['earned'], isNull);
    });

    test('alone, sweet-talk then an offer is just a haggle; same person twice is no combo', () async {
      final (g, id) = await haggle();
      await g.move(id, text: 'wah auntie your mangoes look so nice!');
      var r = await g.move(id, text: '\$12 can?');
      expect(r['combo'], isFalse);
      await g.move(id, text: 'auntie you so pretty today', friend: 'Melody');
      r = await g.move(id, text: '\$12.50 can?', friend: 'Melody');
      expect(r['combo'], isFalse);
      expect(r['combos'], 0);
    });

    test('no combo right after she was made cross', () async {
      final (g, id) = await haggle();
      var r = await g.move(id, text: '\$2', friend: 'Melody'); // an insult of an offer
      expect(['insulted', 'rude'], contains(r['event']));
      r = await g.move(id, text: '\$12 can?');
      expect(r['combo'], isFalse);
    });
  });

  group('🔔 the daily reminder plan', () {
    final names = {'mei': 'Auntie Mei', 'lim': 'Uncle Lim', 'raj': 'Boss Raj', 'wong': 'Uncle Wong'};

    test('a week ahead at the chosen time; today only if it is still ahead and not played yet', () {
      final morning = DateTime(2026, 12, 1, 9);
      var p = planReminders(now: morning, hour: 19, minute: 30, playedToday: false, stallNames: names);
      expect(p.length, 7);
      expect(p.first.at, DateTime(2026, 12, 1, 19, 30));
      expect(p.map((x) => x.at.hour).toSet(), {19});
      p = planReminders(now: morning, hour: 19, minute: 30, playedToday: true, stallNames: names);
      expect(p.length, 6);
      expect(p.first.at, DateTime(2026, 12, 2, 19, 30));
      p = planReminders(now: DateTime(2026, 12, 1, 20), hour: 19, minute: 30, playedToday: false, stallNames: names);
      expect(p.first.at.day, 2);
      expect(p.every((x) => x.title.isNotEmpty && x.body.isNotEmpty), isTrue);
    });

    test('a legendary day says so; the same day gets the same reminder on every phone', () {
      final day = legendDay();
      final p = planReminders(
        now: DateTime(day.year, day.month, day.day, 8),
        hour: 19,
        minute: 0,
        playedToday: false,
        stallNames: names,
        days: 1,
      );
      expect(p.single.title, contains('Legendary'));
      expect(p.single.body, contains(legendaryOn(dayKey(day))!.$2['name']));
      final again = planReminders(
        now: DateTime(day.year, day.month, day.day, 8),
        hour: 19,
        minute: 0,
        playedToday: false,
        stallNames: names,
      );
      expect(again.first.body, p.single.body);
    });
  });
}
