// Friendship, Mum's daily list and streaks, stickers, unlocks: the game around the haggles.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/progress.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  DateTime t = DateTime(2026, 11, 24, 10);
  DateTime call() => t;
  void nextDay([int n = 1]) => t = t.add(Duration(days: n));
}

Future<(Game, MemoryKeyValue, Clock)> newGame({Map<String, Object?>? profile, bool unlockAll = false}) async {
  final store = MemoryKeyValue();
  if (profile != null) await store.write('profile', jsonEncode(profile));
  final clock = Clock();
  final game = Game(content: content, store: store, now: clock.call, unlockAll: unlockAll);
  await game.load();
  return (game, store, clock);
}

/// Play one haggle to the end: buy at the asking price, walk away, or lose to the rival.
Future<Map> finishHaggle(Game g, String stall, String item, {String how = 'buy', String surprise = 'none'}) async {
  var r = await g.start(stall, item, surprise);
  final id = r['id'] as String;
  for (var i = 0; i < 20 && r['done'] != true; i++) {
    r = switch (how) {
      'buy' => await g.move(id, move: 'buy'),
      'walk' => await g.move(id, move: 'walk'),
      'chat' => await g.move(id, text: "how's your day?"),
      _ => throw ArgumentError(how),
    };
  }
  return r;
}

void main() {
  test("a test-12 profile loads, and past haggles count towards friendship and stickers", () async {
    final (game, store, _) = await newGame(
      profile: {
        'name': 'Shiok Otter 123',
        'haggles': [
          for (var i = 0; i < 4; i++)
            {
              'stall': 'mei',
              'item': 'durian',
              'result': 'deal',
              'deal': 18,
              'stars': 3,
              'saved': 0.44,
              'at': '2026-11-20T10:00:00',
            },
          {
            'stall': 'lim',
            'item': 'pomfret',
            'result': 'walked',
            'deal': null,
            'stars': 0,
            'saved': 0,
            'at': '2026-11-20T11:00:00',
          },
        ],
        'reports': [],
      },
    );
    expect(game.me()['name'], 'Shiok Otter 123');
    expect(game.progress.hearts('mei'), 2); // 4 deals x 8 points
    final earned = {
      for (final s in game.stickers())
        if (s['earned'] != null) s['id'],
    };
    expect(earned, containsAll(['first_deal', 'three_stars', 'friend']));
    final saved = jsonDecode((await store.read('profile'))!) as Map;
    expect(saved['friends'], isNotNull); // migrated profile is saved
    await game.deleteAll();
    expect(game.stickers().where((s) => s['earned'] != null), isEmpty);
    expect(game.progress.hearts('mei'), 0);
  });

  test("Mum's list: same for everyone on a day, two different first stalls, budget from fair prices", () async {
    final (a, _, ca) = await newGame();
    final (b, _, _) = await newGame();
    final ta = a.today(), tb = b.today();
    expect(jsonEncode(ta['items']), jsonEncode(tb['items']));
    final items = (ta['items'] as List).cast<Map>();
    expect(items, hasLength(2));
    expect(items[0]['stall'], isNot(items[1]['stall']));
    for (final i in items) {
      expect(baseStalls, contains(i['stall']));
      expect(i.containsKey('floor'), isFalse);
    }
    final fair = items.fold<double>(0, (s, i) => s + (i['fair'] as num));
    expect(ta['budget'], (fair * 1.05).ceilToDouble());
    final lists = <String>{};
    for (var d = 0; d < 20; d++) {
      lists.add(jsonEncode(a.today()['items']));
      ca.nextDay();
    }
    expect(lists.length, greaterThan(5)); // changes from day to day
  });

  test('finishing the list: Mum\'s note, stickers, and a streak that survives days in a row but not a gap', () async {
    final (g, _, clock) = await newGame();
    Future<Map> doList() async {
      Map? last;
      for (final i in (g.today()['items'] as List).cast<Map>()) {
        last = await finishHaggle(g, i['stall'] as String, i['item'] as String);
      }
      return last!;
    }

    final r = await doList();
    expect('${r['mum']}', startsWith('Mum:'));
    expect(g.today()['complete'], isTrue);
    expect(g.today()['under'], isFalse); // paid the asking price: over budget
    expect('${r['mum']}', contains('over budget'));
    expect(r['new_stickers'], contains('list_done'));
    expect(g.progress.streak(), 1);
    clock.nextDay();
    await doList();
    expect(g.progress.streak(), 2);
    clock.nextDay();
    final r3 = await doList();
    expect(g.progress.streak(), 3);
    expect(r3['new_stickers'], contains('streak3'));
    clock.nextDay(2); // missed a day
    expect(g.progress.streak(), 0);
    await doList();
    expect(g.progress.streak(), 1);
  });

  test('friendship: deals and kindness raise it, at most 15 a day per stall; rudeness costs 10', () async {
    final (g, _, clock) = await newGame();
    for (var i = 0; i < 5; i++) {
      await finishHaggle(g, 'raj', 'case');
    }
    expect(g.progress.points('raj'), 15); // capped for the day
    clock.nextDay();
    await finishHaggle(g, 'raj', 'case');
    expect(g.progress.points('raj'), 23);
    final s = await g.start('raj', 'case', 'none');
    await g.move(s['id'] as String, text: 'stupid');
    expect(g.progress.points('raj'), 13);
    final note = g.progress.memoryNote('raj', 'Shiok Otter 123');
    expect(note, contains('many times')); // six visits
    expect(RegExp(r'\d').hasMatch(note), isFalse); // number-free for the AI
  });

  test('friends start in a better mood, never with a lower opening price', () async {
    final (g, _, clock) = await newGame();
    for (var d = 0; d < 6; d++) {
      await finishHaggle(g, 'siti', 'kueh');
      await finishHaggle(g, 'siti', 'kueh');
      clock.nextDay();
    }
    expect(g.progress.hearts('siti'), 3);
    final r = await g.start('siti', 'kueh', 'none');
    expect(r['hearts'], 3);
    expect(r['ask'], r['opening']);
    expect(r['opening'], 14);
    expect(r['mood'], greaterThan(0));
    final p = g.stallProfile('siti');
    expect((p['story'] as List).whereType<String>(), hasLength(3)); // whole backstory unlocked
  });

  test('locked stalls open with stars, with a sticker and a notice', () async {
    final (g, _, _) = await newGame();
    await expectLater(g.start('lee', 'oolong'), throwsA(isA<GameError>()));
    final stalls = (g.stalls()['stalls'] as List).cast<Map>();
    expect(stalls.firstWhere((s) => s['id'] == 'lee')['locked'], isTrue);
    expect(stalls.firstWhere((s) => s['id'] == 'mei')['locked'], isFalse);
    // stars come from the best result on each item: 3 stars needs a price near the secret lowest one
    Map? last;
    for (final (st, it, price) in [('mei', 'durian', 18), ('mei', 'mango', 10), ('lim', 'pomfret', 13)]) {
      final r = await g.start(st, it, 'none');
      final id = r['id'] as String;
      var x = await g.move(id, text: 'I only have \$${price - 2}'); // her real best price
      x = await g.move(id, text: '\$${x['ask']} ok I take');
      last = x['pending'] != null ? await g.move(id, move: 'confirm') : x;
    }
    expect(g.progress.bestStars(), greaterThanOrEqualTo(8));
    expect(last!['unlocked'], contains('lee'));
    expect(last['new_stickers'], contains('new_stall'));
    expect((await g.start('lee', 'oolong', 'none'))['stall'], 'lee');
  });

  test('every sticker can be earned', () async {
    final (g, _, clock) = await newGame(unlockAll: true);
    // market surprises and the rival auntie
    for (final ev in ['rain', 'closing', 'festival', 'rival']) {
      await finishHaggle(g, 'raj', 'powerbank', surprise: ev);
    }
    await finishHaggle(g, 'lim', 'prawns', how: 'chat', surprise: 'rival'); // too slow: Auntie Rose buys it
    // all four first stalls; Mum's list
    for (final st in baseStalls) {
      await finishHaggle(
        g,
        st,
        ((content['stalls'] as List).firstWhere((s) => s['id'] == st)['items'] as List).first['id'],
      );
    }
    for (var d = 0; d < 3; d++) {
      for (final i in (g.today()['items'] as List).cast<Map>()) {
        final r = await g.start(i['stall'] as String, i['item'] as String, 'none');
        final id = r['id'] as String;
        var x = await g.move(id, text: 'I only have \$1'); // insulted...
        x = await g.move(id, text: 'I only have \$${((i['fair'] as num) * 0.7).floor()}'); // ...then her best price
        x = await g.move(id, text: '\$${x['ask']} ok I take');
        if (x['pending'] != null) await g.move(id, move: 'confirm');
      }
      clock.nextDay();
    }
    // friendship with Uncle Lim, then best friends
    for (var d = 0; d < 6; d++) {
      await finishHaggle(g, 'lim', 'pomfret');
      await finishHaggle(g, 'lim', 'pomfret');
      clock.nextDay();
    }
    // final-final price: walk away until called back, then buy
    for (var i = 0; i < 40 && !g.stickers().any((s) => s['id'] == 'final_final' && s['earned'] != null); i++) {
      final r = await g.start('boy', 'rccar', 'none');
      final id = r['id'] as String;
      await g.move(id, text: '30');
      final w = await g.move(id, move: 'walk');
      if (w['event'] == 'callback') await g.move(id, move: 'buy');
    }
    // half price, in a festival (prices start higher)
    for (var i = 0; i < 10; i++) {
      final r = await g.start('mei', 'durian', 'festival');
      final id = r['id'] as String;
      for (var k = 0; k < 3; k++) {
        await g.move(id, pick: 2);
      }
      var x = await g.move(id, text: 'I only have \$15');
      x = await g.move(id, text: '\$${x['ask']} ok I take');
      if (x['pending'] != null) await g.move(id, move: 'confirm');
    }
    // hard mode
    await g.setHard(true);
    await finishHaggle(g, 'siti', 'scarf');
    // a stall unlocked (from a fresh, locked game)
    final (g2, _, _) = await newGame();
    for (final (st, it, price) in [('mei', 'durian', 18), ('mei', 'mango', 10), ('lim', 'pomfret', 13)]) {
      final r = await g2.start(st, it, 'none');
      final id = r['id'] as String;
      var x = await g2.move(id, text: 'I only have \$${price - 2}');
      x = await g2.move(id, text: '\$${x['ask']} ok I take');
      if (x['pending'] != null) await g2.move(id, move: 'confirm');
    }
    final earned = {
      for (final s in [...g.stickers(), ...g2.stickers()])
        if (s['earned'] != null) s['id'],
    };
    final missing = {for (final (id, _, _, _) in stickerDefs) id}.difference(earned);
    expect(missing, isEmpty, reason: 'never earned: $missing');
  });

  test(
    "Mum's list keeps your best price per piece, and a better deal can turn over budget into under budget",
    () async {
      final (g, _, _) = await newGame();
      final items = (g.today()['items'] as List).cast<Map>();
      // first: both bought at the asking price (over budget)
      for (final i in items) {
        await finishHaggle(g, i['stall'] as String, i['item'] as String);
      }
      expect(g.today()['complete'], isTrue);
      expect(g.today()['under'], isFalse);
      final paidFirst = ((g.today()['items'] as List).first as Map)['paid'] as num;
      // then a much better deal on the first item: the list takes the lower price
      final first = items.first;
      final r = await g.start(first['stall'] as String, first['item'] as String, 'none');
      final id = r['id'] as String;
      var x = await g.move(id, text: 'I only have \$${((first['fair'] as num) * 0.8).floor()}'); // her real best price
      x = await g.move(id, text: '\$${x['ask']} ok I take');
      if (x['pending'] != null) x = await g.move(id, move: 'confirm');
      final paidNow = ((g.today()['items'] as List).first as Map)['paid'] as num;
      expect(paidNow, lessThan(paidFirst));
      expect(paidNow, x['deal']);
      expect('${x['mum']}'.toLowerCase(), contains('better'));
      // a worse deal later doesn't replace it
      await finishHaggle(g, first['stall'] as String, first['item'] as String);
      expect(((g.today()['items'] as List).first as Map)['paid'], paidNow);
    },
  );

  test("buying two counts the price per piece on Mum's list", () async {
    final (g, _, _) = await newGame();
    final i = (g.today()['items'] as List).cast<Map>().first;
    final r = await g.start(i['stall'] as String, i['item'] as String, 'none');
    final id = r['id'] as String;
    var x = await g.move(id, text: 'I take two, cheaper?');
    x = await g.move(id, move: 'buy');
    expect(x['qty'], 2);
    expect(((g.today()['items'] as List).first as Map)['paid'], x['deal']); // per piece, not doubled
  });

  test('past haggles keep the whole chat (AI lines marked), newest first, the last 30, wiped with my data', () async {
    final (g, _, _) = await newGame();
    final r = await g.start('mei', 'durian', 'none');
    await g.move(r['id'] as String, text: 'wah so expensive');
    await g.move(r['id'] as String, move: 'walk');
    final h = g.history();
    expect(h, hasLength(1));
    expect(h.first['item_name'], 'durian (1 kg)');
    expect(h.first['result'], anyOf('walked', 'deal'));
    final one = g.historyItem(h.first['id'] as String);
    final chat = (one['chat'] as List).cast<Map>();
    expect(chat.first['who'], 'them'); // her greeting
    expect(chat.map((m) => m['text']), contains('wah so expensive'));
    for (var i = 0; i < 35; i++) {
      await finishHaggle(g, 'raj', 'case');
    }
    expect(g.history(), hasLength(30));
    expect(g.history().first['stall'], 'raj'); // newest first
    expect(() => g.historyItem('nope'), throwsA(isA<GameError>()));
    await g.deleteAll();
    expect(g.history(), isEmpty);
  });
}
