// Release 57: what you buy shows at your stall; customer orders; money celebrations; play-streak rewards; a trophy
// shelf; Mum guides your first sale.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/core/challenges.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/treats.dart';
import 'package:hawker_haggle/extras.dart' show InventoryScreen, ShopPanel;
import 'package:hawker_haggle/sfx.dart';
import 'package:hawker_haggle/shop_screen.dart';
import 'package:hawker_haggle/widgets.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  DateTime t = DateTime(2026, 12, 2, 10);
  DateTime call() => t;
  void nextDay() => t = DateTime(t.year, t.month, t.day + 1, 10);
}

Future<(Game, Clock, MemoryKeyValue)> newGame({int seed = 3}) async {
  final c = Clock();
  final store = MemoryKeyValue();
  final g = Game(
    content: content,
    store: store,
    random: math.Random(seed),
    surprises: false,
    unlockAll: true,
    walletOn: true,
    now: c.call,
  );
  await g.load();
  g.me();
  return (g, c, store);
}

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

void main() {
  setUp(() => Sfx.available = false);

  group('⛱️ what you buy shows at your stall', () {
    test('the stall view lists the things you own that can be seen', () async {
      final (g, _, _) = await newGame();
      expect((await g.shopStart())['decor'], isEmpty);
      await own(g, ['awning', 'balloons', 'neon', 'cake']);
      final decor = ((await g.shopStart())['decor'] as List).cast<String>();
      expect(decor, containsAll(['awning', 'balloons', 'neon']));
      expect(decor, isNot(contains('cake')), reason: 'Mum ate it');
    });

    testWidgets('on screen: the awning, balloons and a glowing sign', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 228, child: StallDecor(owned: {'awning', 'balloons', 'neon', 'radio'})),
          ),
        ),
      );
      for (final k in ['decor_awning', 'decor_balloons', 'decor_sign', 'decor_radio']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.text('💡 OPEN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('📋 customer orders', () {
    test('an order comes in; accept it, buy what they want, deliver it for more than the market asks', () async {
      final (g, _, _) = await newGame();
      final o = g.order()!;
      expect(o['state'], 'offered');
      expect(o['pay'] as num, greaterThan(0));
      await g.answerOrder(yes: true);
      expect(g.order()!['state'], 'active');
      await expectLater(g.deliverOrder(), throwsA(isA<GameError>()), reason: 'nothing in stock yet');
      g.progress.receive(200);
      final qty = (o['qty'] as num).toInt();
      for (var i = 0; i < qty; i++) {
        await buyNow(g, '${o['stall']}', '${o['item']}');
      }
      expect(g.order()!['have'], qty);
      final before = g.progress.wallet;
      final done = await g.deliverOrder();
      expect(done['paid'], o['pay']);
      expect(done['state'], 'done');
      expect(g.progress.wallet, before + (o['pay'] as num));
      expect(g.progress.stock.where((x) => x['key'] == '${o['stall']}/${o['item']}'), isEmpty);
      // the market's price for that many, a little less than the pay
      final ask =
          ((content['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == o['stall'])['items'] as List)
                  .cast<Map>()
                  .firstWhere((i) => i['id'] == o['item'])['ask']
              as num;
      expect(o['pay'] as num, greaterThan(ask * qty));
    });

    test('not delivered by the day after: missed (no penalty), and a new one comes in; turning one down', () async {
      final (g, c, _) = await newGame();
      await g.answerOrder(yes: true);
      c.nextDay();
      expect(g.order()!['state'], 'active', reason: 'due tomorrow: still on');
      c.nextDay();
      final me = g.me();
      expect((me['morning'] as Map)['order_missed'], isNotNull);
      expect(g.order()!['state'], 'offered', reason: 'a new one');
      await g.answerOrder(yes: false);
      expect(g.order()!['state'], 'declined');
      await expectLater(g.answerOrder(yes: true), throwsA(isA<GameError>()));
    });

    test('orders only ask for things you can sell, at stalls that are open, by tomorrow', () async {
      for (var seed = 0; seed < 20; seed++) {
        final (g, c, _) = await newGame(seed: seed);
        for (var d = 0; d < 5; d++) {
          final o = g.order()!;
          final key = '${o['stall']}/${o['item']}';
          expect(g.progress.goesToStock('${o['stall']}', '${o['item']}'), isTrue, reason: key);
          expect(DateTime.parse('${o['due']}').difference(DateTime.parse('${o['day']}')).inDays, 1);
          c.nextDay();
          g.me();
        }
      }
    });
  });

  group('🎉 celebrations', () {
    test('the money in a result card: every +\$X, Mum\'s change, a sale', () {
      expect(moneyIn(['🎯 Daily challenge done! +60 XP, +\$10', '📋 Weekly quest done! +60 XP, +\$5']), 15);
      expect(moneyIn(['👛 Mum: Keep the change! \$3.50 into your wallet.']), 3.5);
      expect(moneyIn(['👛 \$18 into your wallet (\$40 now): \$6 profit!']), 18);
      expect(moneyIn(['👛 You paid \$12. \$48 left in your wallet.']), 0);
    });

    testWidgets('buying in the shop: a party, and "New tier" the first time in a tier', (tester) async {
      final (g, _, store) = await newGame();
      g.progress.addToJar(500);
      await own(g, ['notebook']); // a starter: the growing tier is still new
      await store.write('profile', g.exportProfile());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ShopPanel(
                  api: Api(game: g, content: content, store: store),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      final buy = find.byKey(const ValueKey('buy_cards')); // 💌 a growing-tier thing
      await tester.ensureVisible(buy);
      await tester.pumpAndSettle();
      await tester.tap(buy);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('bought')), findsOneWidget);
      expect(find.textContaining('New tier: Growing'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bought_ok')));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('bought')), findsNothing);
      expect(g.progress.owns('cards'), isTrue);
    });
  });

  group('🔥 the play streak', () {
    test('three days in a row: +\$5 (once), and the earn card counts it', () async {
      final (g, c, _) = await newGame();
      final notes = <String>[];
      for (var d = 0; d < 4; d++) {
        final mum = (g.today()['items'] as List).cast<Map>().first;
        final r = await buyNow(g, '${mum['stall']}', '${mum['item']}');
        notes.addAll((r['notes'] as List).cast<String>());
        c.nextDay();
        g.me();
      }
      expect(notes.where((n) => n.contains('3 days in a row! +\$5')), hasLength(1));
      expect(notes.where((n) => n.contains('days in a row')), hasLength(1), reason: 'not again on day 4');
      expect(Challenges(g.progress).playStreak(), 0, reason: 'not played yet today');
      expect(((g.jar()['earn'] as List).cast<Map>().firstWhere((w) => w['id'] == 'streak'))['done'], isTrue);
      expect(streakRewards[7], 15);
    });
  });

  group('🏆 the trophy shelf; 👩 the first sale', () {
    testWidgets('My things: legendary finds on a shelf', (tester) async {
      final (g, _, store) = await newGame();
      g.progress.p['haggles'] = [
        ...(g.progress.p['haggles'] as List),
        {
          'stall': 'mei',
          'item': 'legend_mei',
          'result': 'deal',
          'deal': 50,
          'stars': 2,
          'legendary': true,
          'item_name': 'golden Musang King durian',
          'emoji': '🍈',
          'day': '2026-12-01',
        },
      ];
      await store.write('profile', g.exportProfile());
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryScreen(
            api: Api(game: g, content: content, store: store),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      final shelf = find.byKey(const ValueKey('trophy_shelf'));
      await tester.ensureVisible(shelf);
      expect(shelf, findsOneWidget);
      expect(find.descendant(of: shelf, matching: find.text('🍈')), findsOneWidget);
    });

    test('the first sale at your stall is marked (for Mum\'s tips), the next one is not', () async {
      final (g, _, _) = await newGame();
      var s = await g.shopStart();
      expect(s['first_sale'], isTrue);
      s = await g.shopMove(s['id'] as String, take: true);
      expect(s['result'], 'sold');
      expect((await g.shopStart()).containsKey('first_sale'), isFalse);
    });

    testWidgets('on screen: Mum\'s tip during the first sale', (tester) async {
      final (g, _, store) = await newGame();
      await store.write('profile', g.exportProfile());
      await tester.pumpWidget(
        MaterialApp(
          home: ShopScreen(
            api: Api(game: g, content: content, store: store),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('first_sale_tip')), findsOneWidget);
      expect(find.textContaining('Your first customer!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
