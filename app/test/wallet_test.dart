// 👛 The wallet: Mum's pocket money each morning, buying costs money (Mum pays for her list, and you keep the
// change), what you buy is stock you sell at your own stall for money, and you choose what to save in the jar.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/extras.dart' show JarScreen;
import 'package:hawker_haggle/core/challenges.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/voice.dart' show money;
import 'package:hawker_haggle/sfx.dart';

import 'challenges_test.dart' as month show newGame, buy, playKind;

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

/// A game with the wallet on (the app's own default), on a given day.
Future<Game> walletGame(DateTime Function() now, {MemoryKeyValue? store}) async {
  final g = Game(
    content: content,
    store: store ?? MemoryKeyValue(),
    random: math.Random(1),
    surprises: false,
    unlockAll: true,
    now: now,
  );
  await g.load();
  return g;
}

/// Something at the first four stalls that is not on Mum's list today, and costs at most [under].
(String, String, num) notOnList(Game g, {num under = 50}) {
  final list = {for (final i in (g.today()['items'] as List).cast<Map>()) '${i['stall']}/${i['item']}'};
  for (final s in (content['stalls'] as List).cast<Map>().take(4)) {
    for (final i in (s['items'] as List).cast<Map>()) {
      if (!list.contains('${s['id']}/${i['id']}') && (i['ask'] as num) <= under) {
        return ('${s['id']}', '${i['id']}', i['ask'] as num);
      }
    }
  }
  throw StateError('nothing found');
}

/// Buys at her first price (OK lah, then the app's Confirm tap).
Future<Map<String, Object?>> buyNow(Game g, String stall, String item) async {
  final r = await g.start(stall, item, 'none');
  return g.move(r['id'] as String, move: 'buy');
}

void main() {
  setUp(() => Game.testWallet = true); // (the pre-wallet branch has it off: its rules, tested with it on)
  tearDown(() => Game.testWallet = false);

  final day1 = DateTime(2026, 12, 2, 10);
  final day2 = DateTime(2026, 12, 3, 10);

  test('the pre-wallet branch has the wallet off', () async {
    Game.testWallet = null;
    final g = Game(content: content, store: MemoryKeyValue());
    expect(g.walletOn, isFalse);
  });

  test('pocket money: \$50 to start, then \$20 each new market day (once a day)', () async {
    var day = day1;
    final store = MemoryKeyValue();
    var g = await walletGame(() => day, store: store);
    expect(g.me()['wallet'], 50);
    expect(g.me()['pocket'], 50);
    expect(g.me()['wallet'], 50, reason: 'once a day');
    final (stall, item, ask) = notOnList(g, under: 30);
    await buyNow(g, stall, item);
    expect(g.me()['wallet'], 50 - ask);
    day = day2;
    g = await walletGame(() => day, store: store);
    expect(g.me()['wallet'], 70 - ask);
    expect(g.me()['pocket'], 20);
    await g.saveToJar(10); // saving is yours to do: Mum doesn't refill it
    day = DateTime(2026, 12, 4, 10);
    g = await walletGame(() => day, store: store);
    expect(g.me()['wallet'], 80 - ask);
    expect(g.progress.jar, 10);
  });

  test('buying costs money and the item becomes stock; the discount no longer goes into the jar', () async {
    final g = await walletGame(() => day1);
    g.me();
    final (stall, item, _) = notOnList(g, under: 30);
    final r0 = await g.start(stall, item, 'none');
    final id = r0['id'] as String;
    var r = await g.move(id, text: '\$${((r0['ask'] as num) * 0.8).round()} can?');
    if (r['pending'] == null) r = await g.move(id, move: 'accept');
    final paid = r['pending'] as num;
    r = await g.move(id, move: 'confirm');
    expect(r['result'], 'deal');
    expect(g.progress.wallet, 50 - paid);
    expect(g.progress.jar, 0);
    expect(g.progress.stock.single['cost'], paid);
    expect('${r['notes']}', contains('You paid ${money(paid)}'));
  });

  test("Mum pays for her list (it goes home to her), and you keep the change", () async {
    final g = await walletGame(() => day1);
    g.me();
    final t = g.today();
    final items = (t['items'] as List).cast<Map>();
    final budget = t['budget'] as num;
    var paid = 0.0;
    Map<String, Object?>? last;
    for (final i in items) {
      final r0 = await g.start('${i['stall']}', '${i['item']}', 'none');
      expect(r0['mum_pays'], isTrue);
      last = await g.move(r0['id'] as String, move: 'buy');
      paid += (last['deal'] as num).toDouble();
    }
    expect(g.progress.stock, isEmpty, reason: "Mum's things go home to Mum");
    final change = ((budget - paid) * 100).round() / 100;
    if (change > 0) {
      expect(g.progress.wallet, closeTo(50 + change, 0.001));
      expect('${last!['notes']}', contains('Keep the change'));
    } else {
      expect(g.progress.wallet, closeTo(math.max(0, 50 + change), 0.001)); // over budget: the extra is yours to pay
    }
    // buying the same thing again is your own (not Mum's)
    final again = await g.start('${items.first['stall']}', '${items.first['item']}', 'none');
    expect(again['mum_pays'], isFalse);
  });

  test("a deal you can't pay for never closes: you're told why, and the deal stays on the table", () async {
    final g = await walletGame(() => day1);
    g.me();
    g.progress.pay(45); // $5 left
    final (stall, item, ask) = notOnList(g, under: 30);
    final r0 = await g.start(stall, item, 'none');
    final id = r0['id'] as String;
    final r1 = await g.move(id, move: 'accept'); // OK lah at her price: the deal on the table
    expect(r1['pending'], ask);
    for (final close in [
      () => g.move(id, move: 'confirm'),
      () => g.move(id, move: 'buy'),
      () => g.move(id, text: 'ok'),
    ]) {
      await expectLater(close(), throwsA(isA<GameError>().having((e) => e.code, 'code', 402)));
    }
    expect(g.progress.wallet, 5);
    expect(g.progress.stock, isEmpty);
    final still = await g.move(id, move: 'cancel');
    expect(still['done'], isFalse, reason: 'nothing broke: the haggle goes on');
  });

  test('a full stock: no more buying for your stall until you sell (Mum\'s list still fine)', () async {
    final g = await walletGame(() => day1);
    g.me();
    g.progress.receive(500);
    final (stall, item, _) = notOnList(g, under: 30);
    for (var i = 0; i < 10; i++) {
      await buyNow(g, stall, item);
    }
    expect(g.progress.stock.length, 10);
    final r0 = await g.start(stall, item, 'none');
    await expectLater(
      g.move(r0['id'] as String, move: 'buy'),
      throwsA(isA<GameError>().having((e) => e.code, 'code', 409)),
    );
    final mum = (g.today()['items'] as List).cast<Map>().first;
    final r = await buyNow(g, '${mum['stall']}', '${mum['item']}');
    expect(r['result'], 'deal');
    expect(g.progress.stock.length, 10);
  });

  test('buying two costs twice', () async {
    final g = await walletGame(() => day1);
    g.me();
    final (stall, item, _) = notOnList(g, under: 25);
    final r0 = await g.start(stall, item, 'none');
    final id = r0['id'] as String;
    final two = await g.move(id, text: 'I take two, cheaper?');
    expect(two['qty'], 2);
    final r = await g.move(id, move: 'buy');
    expect(g.progress.wallet, closeTo(50 - 2 * (r['deal'] as num), 0.001));
    expect(g.progress.stock.length, 2);
  });

  test('your stall: a sale puts the money in your wallet; three wholesale goods a day', () async {
    final g = await walletGame(() => day1);
    g.me();
    final (stall, item, ask) = notOnList(g, under: 30);
    await buyNow(g, stall, item);
    final before = g.progress.wallet;
    var s = await g.shopStart();
    expect((s['product'] as Map)['from'], isNotNull, reason: 'your own stock first');
    s = await g.shopMove(s['id'] as String, take: true);
    expect(s['result'], 'sold');
    final price = (s['price'] ?? s['deal'] ?? s['offer']) as num;
    expect(g.progress.wallet, closeTo(before + price, 0.001));
    expect(g.progress.stock, isEmpty);
    expect('${s['notes']}', contains('into your wallet'));
    // wholesale: the price less what the wholesaler charges, three a day
    for (var i = 0; i < 3; i++) {
      final w = await g.shopStart();
      final cost = (w['product'] as Map)['cost'] as num;
      final before = g.progress.wallet;
      final x = await g.shopMove(w['id'] as String, take: true);
      final p = (x['price'] ?? x['deal'] ?? x['offer']) as num;
      expect(g.progress.wallet, closeTo(before + math.max(0, p - cost), 0.001));
    }
    await expectLater(g.shopStart(), throwsA(isA<GameError>().having((e) => e.code, 'code', 409)));
  });

  test('saving: from the wallet into the jar, never more than you have', () async {
    final g = await walletGame(() => day1);
    g.me();
    final r = await g.saveToJar(20);
    expect(r['saved'], 20);
    expect(r['wallet'], 30);
    expect(r['jar'], 20);
    final all = await g.saveToJar(999);
    expect(all['saved'], 30);
    expect(all['wallet'], 0);
    await expectLater(g.saveToJar(5), throwsA(isA<GameError>()));
  });

  test('co-op: the friend who started it pays and keeps it; the other friend gets the stars, not the goods', () async {
    final g = await walletGame(() => day1);
    g.me();
    final (stall, item, _) = notOnList(g, under: 30);
    await g.coopFinish(
      stall: stall,
      item: item,
      view: {'result': 'deal', 'deal': 12, 'stars': 2, 'saved': 0.3, 'qty': 1, 'opening': 18, 'moves': 3},
      host: 'Melody',
    );
    expect(g.progress.stock, isEmpty);
    expect(g.progress.wallet, 50);
    expect(g.progress.jar, 0);
  });

  testWidgets('the jar screen: what is in your wallet, and Save buttons that move it into the jar', (tester) async {
    Sfx.available = false; // no audio plugin in tests
    final store = MemoryKeyValue();
    final g = await walletGame(() => day1, store: store);
    g.me();
    await store.write('profile', g.exportProfile()); // (the market has opened: Mum's pocket money, saved)
    await tester.pumpWidget(
      MaterialApp(
        home: JarScreen(
          api: Api(game: g, content: content, store: store),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // the API's first load
    await tester.pumpAndSettle();
    expect(find.text('👛 In your wallet: \$50'), findsOneWidget);
    expect(find.byKey(const ValueKey('save_all')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save_10')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('👛 In your wallet: \$40'), findsOneWidget);
    expect(find.text('\$10'), findsWidgets); // the jar
    expect(g.progress.jar, 10);
    await tester.pump(const Duration(seconds: 5)); // the note goes away
  });

  test('a month with the wallet: Mum\'s list, the daily challenge and the stories still come, never stuck', () async {
    // the casual player from challenges_test, with real money: Mum's list, today's challenge, one more haggle
    final (g, clock) = await month.newGame();
    expect(g.walletOn, isTrue);
    var blocked = 0, dailies = 0;
    for (var day = 1; day <= 30; day++) {
      g.me(); // opens the game: pocket money
      for (final i in (g.today()['items'] as List).cast<Map>()) {
        await month.buy(g, i['stall'] as String, i['item'] as String); // Mum pays
      }
      final d = Challenges(g.progress).daily();
      final st = d.stall.isEmpty ? 'mei' : d.stall;
      final items = ((content['stalls'] as List).firstWhere((s) => s['id'] == st)['items'] as List).cast<Map>();
      // the item the challenge names, or (any deal will do) the cheapest one, like a kid with pocket money would
      final cheapest = ([...items]..sort((a, b) => (a['ask'] as num).compareTo(b['ask'] as num))).first;
      final item = items.firstWhere((i) => d.how.contains('${i['name']}'), orElse: () => cheapest)['id'] as String;
      var short = false;
      try {
        if (d.id != 'final_final') await month.playKind(g, d, st, item);
      } on GameError catch (e) {
        expect(e.code, anyOf(402, 409), reason: 'only money or room stops a purchase');
        short = true;
      }
      final done = Challenges(g.progress).dailyDone();
      if (done) dailies++;
      if (short && !done) {
        blocked++; // the challenge really was missed for want of money
        debugPrint('day $day ${d.id} at $st/$item missed: wallet \$${g.progress.wallet}');
      }
      // sells what they bought, a couple a day
      for (var k = 0; k < 2 && g.progress.stock.isNotEmpty; k++) {
        final s = await g.shopStart();
        await g.shopMove(s['id'] as String, take: true);
      }
      expect(g.progress.wallet, greaterThanOrEqualTo(0));
      clock.nextDay();
    }
    expect(g.progress.daysPlayed(), 30);
    for (final id in ['days3', 'dailies7', 'week_done', 'month', 'list_done', 'streak3']) {
      expect(g.stickers().firstWhere((s) => s['id'] == id)['earned'], isNotNull, reason: id);
    }
    expect(dailies, greaterThanOrEqualTo(20), reason: 'daily challenges done: $dailies of 30');
    expect(blocked, lessThanOrEqualTo(3), reason: 'daily challenges missed for want of money: $blocked of 30');
    debugPrint(
      'wallet month: $dailies dailies done, $blocked days out of reach, '
      'wallet \$${g.progress.wallet}, stock ${g.progress.stock.length}',
    );
  });
}
