// Legendary items, tag-team combos in co-op, and the daily reminder plan.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/festivals.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/legendary.dart';
import 'package:hawker_haggle/core/progress.dart' show dayKey;
import 'package:hawker_haggle/reminder.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

/// The first day from 1 Dec 2026 with a legendary item at [stall] (or any stall).
DateTime legendDay([String? stall]) {
  for (var d = DateTime(2026, 12, 1, 10); ; d = d.add(const Duration(days: 1))) {
    final l = legendaryOn(dayKey(d));
    if (l != null && (stall == null || l.stall == stall)) return d;
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
    test('about one day in four, the same stall and item for everyone; every item turns up within two years', () {
      var legendDays = 0;
      final seen = <String>{};
      // two years from the start of the rotation (the festival list runs to the end of 2027)
      for (var d = DateTime(2026, 12, 1); d.isBefore(DateTime(2028, 12, 1)); d = d.add(const Duration(days: 1))) {
        final l = legendaryOn(dayKey(d));
        if (l == null) continue;
        legendDays++;
        seen.add('${l.item['id']}');
        expect(legendaryOn(dayKey(d)), l); // the same, whoever asks
      }
      expect(legendDays, inInclusiveRange(140, 270)); // a quarter of the days, plus the festival specials
      final all = {for (final items in legendaryByStall.values) ...items.map((i) => '${i['id']}')};
      expect(all.length, 33 + festivalSpecials.length);
      expect(seen, all);
      for (final items in legendaryByStall.values) {
        for (final l in items) {
          final ask = (l['ask'] as num), floor = (l['floor'] as num), fair = (l['fair'] as num);
          expect(floor < fair && fair < ask, isTrue, reason: '${l['id']}');
          expect(floor / ask, greaterThan(0.62), reason: '${l['id']} has less room to bargain than usual');
          expect((l['facts'] as List).join(' '), isNot(contains(r'$')), reason: 'no prices in facts');
        }
      }
    });

    test('the days already announced stay the same: the grouper on 27 Nov, the tea cake on 30 Nov', () {
      expect(legendaryOn('2026-11-27')!.item['id'], 'legend_lim');
      expect(legendaryOn('2026-11-30')!.item['id'], 'legend_lee');
    });

    test('festival specials: on the 2nd and 5th day of each festival week, at their stall', () {
      for (final f in festivals) {
        final first = DateTime.parse(f.from);
        final special = festivalSpecials[f.id.replaceAll(RegExp(r'\d+$'), '')]!;
        for (final d in [1, 4]) {
          final l = legendaryOn(dayKey(DateTime(first.year, first.month, first.day + d)))!;
          expect(l.stall, special.$1, reason: f.id);
          expect(l.item['id'], special.$2['id']);
        }
      }
      expect(legendaryOn('2026-12-20')!.item['name'], contains('Christmas')); // the first one: Christmas 2026
    });

    test("the admin's events come first, on every day they cover; sold out once for the whole event", () async {
      final day = ordinaryDay();
      final from = dayKey(day), to = dayKey(day.add(const Duration(days: 2)));
      final events = cleanEvents(
        [
          {
            'id': 7,
            'stall': 'tan',
            'from': from,
            'to': to,
            'item': {
              'name': 'golden jackfruit',
              'emoji': '🟡',
              'fair': 30,
              'ask': 42,
              'floor': 28,
              'facts': ['From a 40-year-old tree in Johor'],
            },
          },
        ],
        {for (final s in content['stalls'] as List) '${s['id']}'},
      );
      expect(events.single['item'], containsPair('id', 'legend_evt_7'));
      expect(legendaryOn(from, events: events)!.stall, 'tan');
      expect(legendaryOn(to, events: events)!.key, 'evt-7');
      expect(nextLegendary(day.subtract(const Duration(days: 1)), events: events), (1, 'tan'));
      final g = await newGame(day, unlockAll: true)
        ..legendEvents = events;
      expect((g.stalls()['legendary'] as Map)['name'], 'golden jackfruit');
      final r = await tapThrough(g, await g.start('tan', 'legend_evt_7'));
      expect(r['result'], 'deal');
      // the next day of the same event: still sold out
      final g2 = Game(
        content: content,
        store: g.store,
        surprises: false,
        unlockAll: true,
        now: () => day.add(const Duration(days: 1)),
      );
      await g2.load();
      g2.legendEvents = events;
      expect((g2.stalls()['legendary'] as Map)['sold_out'], isTrue);
      await expectLater(g2.start('tan', 'legend_evt_7'), throwsA(isA<GameError>()));
      // after the event is gone, the history still knows what it was
      g2.legendEvents = const [];
      expect(g2.history().first['item_name'], 'golden jackfruit');
      expect(g2.history().first['emoji'], '🟡');
    });

    test('events that fail the checks never reach the game (their facts would go to the AI)', () {
      final stalls = {'mei', 'tan'};
      Map ev(Map<String, Object?> over, [Map<String, Object?> item = const {}]) => {
        'id': 1,
        'stall': 'mei',
        'from': '2027-01-04',
        'to': '2027-01-05',
        ...over,
        'item': {
          'name': 'golden jackfruit',
          'emoji': '🟡',
          'fair': 30,
          'ask': 42,
          'floor': 28,
          'facts': ['Sweet and crunchy'],
          ...item,
        },
      };
      expect(cleanEvents([ev({})], stalls), hasLength(1));
      for (final bad in [
        ev({'stall': 'nowhere'}),
        ev({'id': 'x'}),
        ev({'to': '2027-02-01'}), // longer than a week
        ev({'to': '2027-01-01'}), // ends before it starts
        ev({}, {'name': 'see http://x.example'}),
        ev({}, {'name': 'a {b} <c>'}),
        ev({}, {'emoji': 'abc'}),
        ev({}, {'fair': 50}),
        ev({}, {'floor': 10}),
        ev({}, {'facts': <String>[]}),
        ev({}, {
          'facts': [r'costs $5'],
        }),
        ev({}, {'facts': 'just text'}),
      ]) {
        expect(cleanEvents([bad], stalls), isEmpty, reason: '$bad');
      }
      // overlapping days: the first one wins
      expect(
        cleanEvents([
          ev({}),
          ev({'id': 2, 'from': '2027-01-05', 'to': '2027-01-06'}),
        ], stalls),
        hasLength(1),
      );
      expect(cleanEvents('nonsense', stalls), isEmpty);
    });

    test('it shows at its stall and on top of the market, opens even at a locked stall, and is harder', () async {
      final day = legendDay('wong'); // Uncle Wong opens on day 7: locked for a new player
      final l = legendaryOn(dayKey(day))!;
      final g = await newGame(day);
      final s = g.stalls();
      final banner = s['legendary'] as Map;
      expect(banner['stall'], 'wong');
      expect(banner['name'], l.item['name']);
      final wong = (s['stalls'] as List).cast<Map>().firstWhere((x) => x['id'] == 'wong');
      expect(wong['locked'], isTrue);
      expect((wong['items'] as List).cast<Map>().last['legendary'], isTrue);
      final r = await g.start('wong', '${l.item['id']}', 'rain');
      expect(r['legendary'], isTrue);
      expect(r['surprise'], ''); // no market surprise on a legendary haggle
      expect(r['patience'], 75);
      expect(r['ask'], l.item['ask']);
    });

    // every built-in item and festival special can be won with taps (each played as a one-day event)
    var n = 0;
    for (final e in legendaryByStall.entries) {
      for (final item in e.value) {
        final id = ++n;
        test('${item['id']}: winnable with taps only; then sold out, in the history, with its sticker', () async {
          final day = ordinaryDay();
          final events = cleanEvents(
            [
              {'id': id, 'stall': e.key, 'from': dayKey(day), 'to': dayKey(day), 'item': item},
            ],
            {e.key},
          );
          expect(events, hasLength(1), reason: '${item['id']} passes the same checks as a posted event');
          final g = await newGame(day, unlockAll: true, seed: id)
            ..legendEvents = events;
          final r = await tapThrough(g, await g.start(e.key, 'legend_evt_$id'));
          expect(r['result'], 'deal', reason: 'taps only should reach a deal for ${item['id']}');
          expect(r['new_stickers'], contains('legend'));
          expect((r['notes'] as List).join(' '), contains('legendary'));
          expect(((g.stalls()['legendary'] as Map)['sold_out']), isTrue);
          await expectLater(g.start(e.key, 'legend_evt_$id'), throwsA(isA<GameError>()));
          final h = g.history().first;
          expect(h['item_name'], item['name']);
          expect(h['emoji'], item['emoji']);
        });
      }
    }

    test('a built-in legendary day: playing the day\'s own item, and the history finds it by id', () async {
      final day = legendDay('mei');
      final l = legendaryOn(dayKey(day))!;
      final g = await newGame(day, unlockAll: true);
      final r = await tapThrough(g, await g.start('mei', '${l.item['id']}'));
      expect(r['result'], 'deal');
      expect(g.history().first['item_name'], l.item['name']);
    });

    test('on other days the market says when and where the next one is, but not what it is', () async {
      final day = ordinaryDay();
      final g = await newGame(day, unlockAll: true);
      final next = g.stalls()['next_legendary'] as Map;
      final (days, stall) = nextLegendary(day)!;
      expect(next['days'], days);
      expect(days, greaterThan(0));
      expect(next['stall'], stall);
      expect(legendaryOn(next['day'] as String)!.stall, stall); // the same day the real schedule says
      expect(next.containsKey('name'), isFalse); // the item stays a surprise
      expect(next.containsKey('emoji'), isFalse);
      // on the day itself: the banner, no teaser
      final g2 = await newGame(legendDay(), unlockAll: true);
      expect(g2.stalls()['next_legendary'], isNull);
      expect(g2.stalls()['legendary'], isNotNull);
    });

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
      expect(p.single.body, contains('${legendaryOn(dayKey(day))!.item['name']}'));
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
