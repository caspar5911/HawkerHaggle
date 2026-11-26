// Release 59: at your stall, customers love different things (and pay more for them), budgets vary from person to
// person, and "Not today" sends a customer away (a few a day).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/shop.dart';
import 'package:hawker_haggle/sfx.dart';
import 'package:hawker_haggle/shop_screen.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  DateTime t = DateTime(2026, 12, 2, 10);
  DateTime call() => t;
  void nextDay() => t = DateTime(t.year, t.month, t.day + 1, 10);
}

Future<(Game, Clock)> newGame({int seed = 3}) async {
  final c = Clock();
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    random: math.Random(seed),
    surprises: false,
    unlockAll: true,
    walletOn: true,
    now: c.call,
  );
  await g.load();
  g.me();
  return (g, c);
}

Future<void> buyNow(Game g, String stall, String item) async {
  final r = await g.start(stall, item, 'none');
  await g.move(r['id'] as String, move: 'buy');
}

void main() {
  setUp(() => Sfx.available = false);

  test('every customer loves one kind of thing, and every kind has someone who loves it', () {
    final kinds = {for (final c in customers) ...c.loves};
    expect(kinds, {'fresh', 'souvenir', 'toy', 'premium'});
    for (final c in customers) {
      expect(c.loves, isNotEmpty, reason: c.id);
      expect(c.clue, isNotEmpty, reason: c.id);
    }
    // every item you can stock has a kind (the bicycle is a day's rental, never stock)
    for (final st in (content['stalls'] as List).cast<Map>()) {
      for (final it in (st['items'] as List).cast<Map>()) {
        final key = '${st['id']}/${it['id']}';
        if (key == 'tan/bicycle') continue;
        expect(kindOf(key), isNot('other'), reason: key);
      }
    }
  });

  test('budgets vary from person to person: the same kind of customer, very different limits', () {
    final taitai = customers.firstWhere((c) => c.id == 'taitai');
    final student = customers.firstWhere((c) => c.id == 'student');
    const p = Product('mango', 'box of mangoes', '🥭', 13, 18);
    final t = [for (var i = 0; i < 300; i++) Sale(p, taitai, seed: i).most];
    final s = [for (var i = 0; i < 300; i++) Sale(p, student, seed: i).most];
    expect(t.reduce(math.max) - t.reduce(math.min), greaterThan(p.fair * 0.3));
    // a generous student can beat a stingy taitai: no one customer is always the best
    expect(s.reduce(math.max), greaterThan(t.reduce(math.min)));
  });

  test('a customer picks what they love from your stock, and pays more for it', () async {
    var seen = 0;
    for (var seed = 0; seed < 40 && seen < 4; seed++) {
      final (g, _) = await newGame(seed: seed);
      g.progress.receive(200); // (enough for scallops)
      await buyNow(g, 'boy', 'yoyo'); // a toy: first in line
      await buyNow(g, 'lee', 'scallops'); // premium
      final r = await g.shopStart();
      final who = (r['customer'] as Map)['id'];
      final what = '${(r['product'] as Map)['id']}';
      if (who == 'taitai') {
        expect(what, 'stock:lee/scallops', reason: 'the taitai loves premium things');
        expect(r['loves'], true);
        seen++;
      } else if (who == 'student') {
        expect(what, 'stock:boy/yoyo');
        expect(r['loves'], true);
        seen++;
      } else {
        expect(what, 'stock:boy/yoyo', reason: 'nothing they love: the next in line');
        expect(r.containsKey('loves'), false);
      }
    }
    expect(seen, greaterThan(0));
  });

  test('"Not today": sends the customer away without touching your stock, three times a day', () async {
    final (g, c) = await newGame();
    await buyNow(g, 'boy', 'yoyo');
    final before = g.progress.stock.length;
    var r = await g.shopStart();
    expect(r['passes_left'], Game.passesPerDay);
    for (var i = 0; i < Game.passesPerDay; i++) {
      final out = await g.shopPass(r['id'] as String);
      expect(out['result'], 'passed');
      expect(out['passes_left'], Game.passesPerDay - i - 1);
      r = await g.shopStart();
    }
    expect(g.progress.stock.length, before, reason: 'sending someone away sells nothing');
    expect(r['passes_left'], 0);
    await expectLater(g.shopPass(r['id'] as String), throwsA(isA<GameError>()));
    // (that customer is still there, and can be served)
    final sold = await g.shopMove(r['id'] as String, take: true);
    expect(sold['done'], true);
    // a new day: three more
    c.nextDay();
    expect((await g.shopStart())['passes_left'], Game.passesPerDay);
  });

  test(
    'your own price: close to their offer they say yes; near their limit they bargain back; again, they give in',
    () {
      final uncle = customers.firstWhere((c) => c.id == 'uncle');
      const p = Product('mango', 'box of mangoes', '🥭', 13, 18);
      var bargained = 0;
      for (var seed = 0; seed < 200; seed++) {
        final s = Sale(p, uncle, seed: seed);
        final near = ((s.most - 0.5) * 2).floor() / 2; // just under their limit
        if (near <= s.offer + (s.most - s.offer) * 0.35) continue;
        expect(s.askFor(near), 'raise', reason: 'they bargain back');
        expect(s.offer, lessThan(near));
        expect(s.askFor(near), 'accept', reason: 'holding firm works within their limit');
        expect(s.price, near);
        bargained++;
      }
      expect(bargained, greaterThan(100));
    },
  );

  testWidgets('on screen: the clue, and "Not today" brings the next customer (until none are left)', (tester) async {
    final c = Clock();
    final store = MemoryKeyValue();
    final g = Game(
      content: content,
      store: store,
      random: math.Random(5),
      surprises: false,
      unlockAll: true,
      walletOn: true,
      now: c.call,
    );
    await g.load();
    g.me();
    await store.write('profile', g.exportProfile());
    await tester.pumpWidget(
      MaterialApp(
        home: ShopScreen(
          api: Api(game: g, content: content, store: store),
        ),
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(seconds: 2));
    }

    await settle();
    expect(find.byKey(const ValueKey('customer_clue')), findsOneWidget);
    for (var left = Game.passesPerDay; left > 0; left--) {
      expect(find.text('👋 Not today ($left)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shop_pass')));
      await settle();
    }
    expect(find.byKey(const ValueKey('shop_pass')), findsNothing, reason: 'none left today');
    expect(find.byKey(const ValueKey('shop_take')), findsOneWidget, reason: 'a customer is still there to serve');
    expect(tester.takeException(), isNull);
  });
}
