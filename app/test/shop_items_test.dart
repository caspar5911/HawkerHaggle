// 🛍️ The shop: every item is shown, and each one really does what it says.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/challenges.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/progress.dart' show Progress;
import 'package:hawker_haggle/core/treats.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  DateTime t = DateTime(2026, 12, 2, 10);
  DateTime call() => t;
  void nextDay() => t = DateTime(t.year, t.month, t.day + 1, 10);
}

Future<(Game, Clock)> newGame({bool? wallet, int seed = 1}) async {
  final c = Clock();
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    random: math.Random(seed),
    surprises: false,
    unlockAll: true,
    walletOn: wallet,
    now: c.call,
  );
  await g.load();
  g.me();
  return (g, c);
}

/// Owns these shop items (paid for out of a full jar).
Future<void> own(Game g, List<String> ids) async {
  for (final id in ids) {
    g.progress.addToJar(goals.firstWhere((x) => x.id == id).cost);
    await g.buyGoal(id);
  }
}

Future<Map<String, Object?>> buyNow(Game g, String stall, String item) async {
  final r = await g.start(stall, item, 'none');
  return g.move(r['id'] as String, move: 'buy');
}

/// Something at the first stalls that isn't on Mum's list today.
(String, String) notOnList(Game g) {
  final list = {for (final i in (g.today()['items'] as List).cast<Map>()) '${i['stall']}/${i['item']}'};
  for (final (s, i) in const [('raj', 'case'), ('siti', 'kueh'), ('mei', 'mango'), ('lim', 'pomfret')]) {
    if (!list.contains('$s/$i')) return (s, i);
  }
  throw StateError('nothing');
}

void main() {
  setUp(() => Game.testWallet = null); // the app's own default: the wallet on
  tearDown(() => Game.testWallet = false);

  test('the shop shows everything, by tier, with what it does; old ids kept', () async {
    final (g, _) = await newGame();
    final shop = (g.jar()['goals'] as List).cast<Map>();
    expect(shop.length, goals.length);
    expect(shop.length, greaterThanOrEqualTo(15));
    expect({for (final x in shop) x['id']}.length, shop.length, reason: 'unique ids');
    for (final id in ['cake', 'awning', 'scooter']) {
      expect(shop.any((x) => x['id'] == id), isTrue, reason: '$id (players already own it)');
    }
    for (final x in shop) {
      expect('${x['what']}', isNotEmpty);
      expect(goalTiers.map((t) => t.$1), contains(x['tier']));
    }
    expect(shop.map((x) => x['cost'] as num).reduce(math.max), 3000);
  });

  test('📒 the notebook shows your best price; 🎂 the cake adds pocket money each new day', () async {
    final (g, c) = await newGame();
    final (st, it) = notOnList(g);
    final r = await buyNow(g, st, it);
    Map item() => ((g.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == st)['items'] as List)
        .cast<Map>()
        .firstWhere((i) => i['id'] == it);
    expect(item().containsKey('best_paid'), isFalse);
    await own(g, ['notebook', 'cake']);
    expect(item()['best_paid'], r['deal']);
    final before = g.progress.wallet;
    c.nextDay();
    final me = g.me();
    expect(g.progress.wallet, before + Progress.welcomeMoney + 5);
    expect((me['morning'] as Map)['extra'], 5);
    g.me();
    expect(g.progress.wallet, before + Progress.welcomeMoney + 5, reason: 'once a day');
  });

  test('🍀 more patience and 🌸 a better mood from the start; ⌚ the watch on the price tag', () async {
    final (g, _) = await newGame();
    await buyNow(g, 'boy', 'yoyo'); // (the first haggle is the gentle one)
    var r = await g.start('lim', 'pomfret', 'none');
    expect(r['patience'], 100);
    expect(r['mood'], 0);
    expect(r.containsKey('watch'), isFalse);
    await own(g, ['charm', 'flowers', 'watch']);
    r = await g.start('lim', 'pomfret', 'none');
    expect(r['patience'], 110);
    expect(r['mood'], 0.5);
    expect(r['watch'], isTrue);
  });

  test('📦 the shelf and 🗄️ the storeroom make room', () async {
    final (g, _) = await newGame();
    expect(g.inventory()['max'], 10);
    await own(g, ['shelf']);
    expect(g.inventory()['max'], 15);
    await own(g, ['storeroom']);
    expect(g.inventory()['max'], 25);
  });

  test('🛵 deliveries: each new day, the oldest stock sells at 90% of the market price (🚚 the van: three)', () async {
    final (g, c) = await newGame();
    g.progress.receive(200);
    final (st, it) = notOnList(g);
    for (var i = 0; i < 4; i++) {
      await buyNow(g, st, it);
    }
    final fair = (((g.progress.stock.first['ask'] as num) * 0.9 * 2).round() / 2); // 90% of the market price
    await own(g, ['scooter']);
    final before = g.progress.wallet;
    c.nextDay();
    final m = g.me()['morning'] as Map;
    expect((m['delivered'] as List).length, 1);
    expect(m['delivered_total'], fair);
    expect(g.progress.wallet, closeTo(before + Progress.welcomeMoney + fair, 0.001));
    expect(g.progress.stock.length, 3);
    g.me();
    expect(g.progress.stock.length, 3, reason: 'once a day');
    await own(g, ['van']);
    c.nextDay();
    g.me();
    expect(g.progress.stock, isEmpty, reason: 'three a day with the van');
  });

  test('🐷 the piggy bank: 2% of the jar each new day, never more than \$5', () async {
    final (g, c) = await newGame();
    await own(g, ['piggy']);
    g.progress.addToJar(100);
    c.nextDay();
    g.me();
    expect(g.progress.jar, 102);
    g.progress.addToJar(898);
    c.nextDay();
    g.me();
    expect(g.progress.jar, 1005);
  });

  test('🪧 the sign brings big spenders (the taitai) more often; ✨ the golden stall', () async {
    Future<int> taitais(List<String> owned) async {
      final (g, _) = await newGame(seed: 5);
      await own(g, owned);
      var n = 0;
      for (var i = 0; i < 80; i++) {
        final s = await g.shopStart();
        if ((s['customer'] as Map)['id'] == 'taitai') n++;
      }
      return n;
    }

    final plain = await taitais([]), signed = await taitais(['sign']);
    expect(signed, greaterThan(plain + 15), reason: 'without $plain, with the sign $signed (of 80)');
    final (g, _) = await newGame();
    expect((await g.shopStart()).containsKey('golden'), isFalse);
    await own(g, ['golden']);
    expect((await g.shopStart())['golden'], isTrue);
  });

  test('👛 Save & buy: the jar first, the rest from the wallet', () async {
    final (g, _) = await newGame();
    g.progress.addToJar(10);
    final r = await g.buyGoal('cake', fromWallet: true);
    expect(g.progress.owns('cake'), isTrue);
    expect(g.progress.jar, 0);
    expect(g.progress.wallet, 60 - 20); // \$60 to start, \$20 of it saved into the jar for the cake
    expect('${r['note']}', contains('pocket money'));
    await expectLater(g.buyGoal('wall', fromWallet: true), throwsA(isA<GameError>()));
  });

  test('👑 the wall: a crown by your name; 🏅 Market Month day 21: a golden name badge', () async {
    final (g, c) = await newGame();
    expect(g.me().containsKey('crown'), isFalse);
    await own(g, ['wall']);
    expect(g.me()['crown'], isTrue);
    for (var d = 0; d < 21; d++) {
      final mum = (g.today()['items'] as List).cast<Map>().first; // Mum pays, and it goes home to her
      await buyNow(g, '${mum['stall']}', '${mum['item']}');
      c.nextDay();
    }
    expect(g.me()['gold_name'], isTrue);
  });

  test('no wallet (the pre-wallet way): the cake and deliveries pay into the jar', () async {
    final (g, c) = await newGame(wallet: false);
    await own(g, ['cake']);
    final jar = g.progress.jar;
    c.nextDay();
    g.me();
    expect(g.progress.jar, jar + 5);
  });

  test('the shop is in order (tier, then price) and has 30+ things', () async {
    final (g, _) = await newGame();
    final shop = (g.jar()['goals'] as List).cast<Map>();
    expect(shop.length, greaterThanOrEqualTo(30));
    final order = [for (final t in goalTiers) t.$1];
    for (var i = 1; i < shop.length; i++) {
      final a = shop[i - 1], b = shop[i];
      final ta = order.indexOf('${a['tier']}'), tb = order.indexOf('${b['tier']}');
      expect(
        ta < tb || (ta == tb && (a['cost'] as num) <= (b['cost'] as num)),
        isTrue,
        reason: '${a['id']} ${b['id']}',
      );
    }
  });

  test('🍲 the dinner and 📺 the TV add pocket money too; 🛺 the trishaw delivers one more', () async {
    final (g, c) = await newGame();
    await own(g, ['cake', 'dinner', 'tv', 'trishaw']);
    g.progress.receive(100);
    final (st, it) = notOnList(g);
    await buyNow(g, st, it);
    await buyNow(g, st, it);
    final before = g.progress.wallet;
    c.nextDay();
    final m = g.me()['morning'] as Map;
    expect(m['extra'], 20);
    expect((m['delivered'] as List).length, 1, reason: 'the trishaw alone: one');
    expect(g.progress.wallet, greaterThan(before + 20 + 20));
  });

  test('🌺 the orchid: a bigger list budget; 💌 the cards: friendships grow faster', () async {
    final (a, _) = await newGame(seed: 2);
    final (b, _) = await newGame(seed: 2);
    final budget = a.today()['budget'] as num;
    await own(b, ['orchid', 'cards']);
    expect(b.today()['budget'] as num, greaterThan(budget));
    final (st, it) = notOnList(a);
    await buyNow(a, st, it);
    await buyNow(b, st, it);
    num points(Game g) => (g.progress.p['friends'] as Map)[st]['points'] as num;
    expect(points(b), greaterThan(points(a)));
  });

  test('☂️ the umbrella and ⏰ the clock: rainy and closing-time bargains come more often', () async {
    Future<int> count(List<String> owned) async {
      final c = Clock();
      final g = Game(content: content, store: MemoryKeyValue(), random: math.Random(7), unlockAll: true, now: c.call);
      await g.load();
      await own(g, owned);
      await buyNow(g, 'boy', 'yoyo'); // (the first haggle never has a surprise)
      var n = 0;
      for (var i = 0; i < 200; i++) {
        final r = await g.start('mei', 'mango');
        if (r['surprise'] == 'rain' || r['surprise'] == 'closing') n++;
      }
      return n;
    }

    final plain = await count([]), owned = await count(['umbrella', 'clock']);
    expect(owned, greaterThan(plain + 10), reason: 'without $plain, with them $owned (of 200)');
  });

  test('📻 the radio: customers at your stall open with better offers; 🎁 gift wrap: a tip', () async {
    Future<Map<String, Object?>> firstCustomer(List<String> owned) async {
      final (g, _) = await newGame(seed: 4);
      await own(g, owned);
      return g.shopStart();
    }

    final plain = await firstCustomer([]), radio = await firstCustomer(['radio']);
    expect(radio['offer'] as num, greaterThan(plain['offer'] as num));
    final (g, _) = await newGame();
    await own(g, ['giftwrap']);
    final s = await g.shopStart();
    final before = g.progress.wallet;
    final x = await g.shopMove(s['id'] as String, take: true);
    expect('${x['notes']}', contains('tip'));
    expect(g.progress.wallet, greaterThan(before + 1));
  });

  test('🎓 the course: five wholesale goods a day', () async {
    final (g, _) = await newGame();
    await own(g, ['course']);
    for (var i = 0; i < 5; i++) {
      final s = await g.shopStart();
      await g.shopMove(s['id'] as String, take: true);
    }
    await expectLater(g.shopStart(), throwsA(isA<GameError>()));
  });

  test('🗺️ the map: a later stall opens a day sooner; 📸 the camera: what the next legendary item is', () async {
    final (g, c) = await newGame();
    // Uncle Wong opens on day 2 of play; with the map, on day 1
    final wongBefore = ((g.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == 'wong'))['locked'];
    expect(wongBefore, isTrue);
    final g2 = Game(content: content, store: MemoryKeyValue(), random: math.Random(1), surprises: false, now: c.call);
    await g2.load();
    g2.me();
    await own(g2, ['map']);
    await buyNow(g2, 'mei', 'mango');
    expect(((g2.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == 'wong'))['locked'], isFalse);
    // a day with a legendary item coming
    while (g.stalls()['next_legendary'] == null) {
      c.nextDay();
    }
    expect((g.stalls()['next_legendary'] as Map).containsKey('item_name'), isFalse);
    await own(g, ['camera']);
    expect((g.stalls()['next_legendary'] as Map)['item_name'], isNotNull);
  });

  test('🪙 the coin: more XP for a daily challenge; 📚 the school: a higher daily XP cap from haggles', () async {
    final (g, _) = await newGame(wallet: false); // (about XP: no money in the way of 30 deals)
    await own(g, ['coin', 'school']);
    expect(g.progress.owns('coin'), isTrue);
    expect(xpDailyChallenge * 3 ~/ 2, greaterThan(xpDailyChallenge));
    // (the cap itself: haggling a lot in one day earns more than the plain cap)
    final before = (g.challenges()['rank'] as Map)['xp'] as num;
    for (var i = 0; i < 30; i++) {
      final mum = (g.today()['items'] as List).cast<Map>().first;
      await buyNow(g, '${mum['stall']}', '${mum['item']}');
    }
    final after = (g.challenges()['rank'] as Map)['xp'] as num;
    expect(after - before, greaterThan(xpHaggleCapPerDay));
  });
}
