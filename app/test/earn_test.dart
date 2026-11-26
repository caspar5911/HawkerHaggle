// 💰 Ways to earn: money for the daily challenge, weekly quests, a new rank, a story chapter and a first ⭐⭐⭐; the
// "How to earn" card in the shop. Every dollar earned shows on the result card: no hidden money.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/challenges.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/progress.dart';

import 'haggle_well.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  DateTime t = DateTime(2026, 12, 2, 10);
  DateTime call() => t;
  void nextDay() => t = DateTime(t.year, t.month, t.day + 1, 10);
}

Future<(Game, Clock)> newGame({bool? wallet}) async {
  final c = Clock();
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    random: math.Random(3),
    surprises: false,
    unlockAll: true,
    walletOn: wallet,
    now: c.call,
  );
  await g.load();
  g.me();
  return (g, c);
}

/// The money a result card says you got: every "+$X", and Mum's change.
double moneyIn(Map r) {
  var sum = 0.0;
  for (final n in (r['notes'] as List? ?? const []).cast<String>()) {
    for (final m in RegExp(r'\+\$(\d+(?:\.\d+)?)').allMatches(n)) {
      sum += double.parse(m[1]!);
    }
    final change = RegExp(r'Keep the change! \$(\d+(?:\.\d+)?)').firstMatch(n);
    if (change != null) sum += double.parse(change[1]!);
    final over = RegExp(r'so \$(\d+(?:\.\d+)?) comes out of your wallet').firstMatch(n);
    if (over != null) sum -= double.parse(over[1]!);
  }
  return sum;
}

/// What a result card says you paid.
double paidOut(Map r) {
  final paid = (r['notes'] as List? ?? const []).cast<String>().map(
    (n) => RegExp(r'You paid \$(\d+(?:\.\d+)?)').firstMatch(n),
  );
  return paid.whereType<RegExpMatch>().fold(0.0, (a, m) => a + double.parse(m[1]!));
}

void main() {
  setUp(() => Game.testWallet = true); // (the pre-wallet branch has it off: earning, tested with the wallet on)
  tearDown(() => Game.testWallet = false);

  test('\$60 to start', () async {
    final (g, _) = await newGame();
    expect(g.progress.wallet, 60);
  });

  test('no hidden money: over a month, the wallet only changes by what the result cards say', () async {
    final (g, c) = await newGame();
    var daily = 0, quests = 0, ranks = 0;
    for (var day = 0; day < 20; day++) {
      g.me(); // (the pocket money: before the haggles, so it's not counted below)
      final mum = (g.today()['items'] as List).cast<Map>();
      final d = Challenges(g.progress).daily();
      final st = d.stall.isEmpty ? 'mei' : d.stall;
      for (final (stall, item) in [
        for (final i in mum) ('${i['stall']}', '${i['item']}'),
        (st, (((content['stalls'] as List).firstWhere((s) => s['id'] == st)['items'] as List).first as Map)['id']),
      ]) {
        final before = g.progress.wallet;
        Map r;
        try {
          r = await haggleWell(g, content, stall, '$item');
        } on GameError {
          continue; // (can't afford it today)
        }
        if (r['done'] != true) continue;
        final notes = '${r['notes']}';
        if (notes.contains('Daily challenge done')) daily++;
        if (notes.contains('Weekly quest done')) quests++;
        if (notes.contains('New rank')) ranks++;
        expect(
          g.progress.wallet,
          closeTo(before + moneyIn(r) - paidOut(r), 0.001),
          reason: 'day $day $stall/$item: ${r['notes']}',
        );
      }
      c.nextDay();
    }
    expect(daily, greaterThan(0));
    expect(quests, greaterThan(0));
    expect(ranks, greaterThan(0));
  });

  test('🎯 the daily challenge pays \$10, 🎖️ a new rank \$5 × the level, ⭐⭐⭐ the first time \$5 (once)', () async {
    final (g, _) = await newGame();
    // a new rank: just short of level 2
    g.progress.p['xp'] = ranks[1].$1 - 1;
    final mum = (g.today()['items'] as List).cast<Map>().first;
    final r = await haggleWell(g, content, '${mum['stall']}', '${mum['item']}');
    expect('${r['notes']}', contains('New rank: ${ranks[1].$2}! +\$${(moneyPerRank * 2).toInt()}'));
    if ((r['stars'] as num) >= 3) {
      expect('${r['notes']}', contains('first three stars'));
      final again = await haggleWell(g, content, '${mum['stall']}', '${mum['item']}');
      if ((again['stars'] as num) >= 3) expect('${again['notes']}', isNot(contains('first three stars')));
    }
    expect(moneyDaily, 10);
    expect(moneyQuest, 5);
    expect(moneyAllQuests, 25);
    expect(storyThanks(0), 10);
    expect(storyThanks(2), 20);
  });

  test('no wallet (the pre-wallet way): the money goes into the jar', () async {
    final (g, _) = await newGame(wallet: false);
    g.progress.p['xp'] = ranks[1].$1 - 1;
    final jar = g.progress.jar;
    final mum = (g.today()['items'] as List).cast<Map>().first;
    final r = await haggleWell(g, content, '${mum['stall']}', '${mum['item']}');
    expect('${r['notes']}', contains('New rank'));
    expect(g.progress.jar, greaterThanOrEqualTo(jar + moneyPerRank * 2));
  });

  test('💡 the How to earn card: every way, ticked off when done, with the next one to try', () async {
    final (g, _) = await newGame();
    var ways = (g.jar()['earn'] as List).cast<Map>();
    expect(
      ways.map((w) => w['id']),
      containsAll(['pocket', 'stall', 'list', 'daily', 'quests', 'stars', 'rank', 'story']),
    );
    expect(ways.firstWhere((w) => w['id'] == 'stall')['done'], isFalse);
    // sell something at your own stall
    final s = await g.shopStart();
    await g.shopMove(s['id'] as String, take: true);
    ways = (g.jar()['earn'] as List).cast<Map>();
    expect(ways.firstWhere((w) => w['id'] == 'stall')['done'], isTrue);
  });

  test('🍱 a nasi lemak tray goes into your stock; 🚲 the bicycle is a rental (shown, not stock)', () async {
    final (g, _) = await newGame();
    g.progress.receive(200);
    final tray = await g.start('rosnah', 'tray', 'none');
    await g.move(tray['id'] as String, move: 'buy');
    expect(g.progress.stock.single['key'], 'rosnah/tray');
    final bike = await g.start('tan', 'bicycle', 'none');
    await g.move(bike['id'] as String, move: 'buy');
    expect(g.progress.stock.length, 1, reason: 'a rental is not stock');
    final inv = g.inventory();
    expect((inv['rented'] as List).single['name'], contains('bicycle'));
    final tan = ((g.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == 'tan')['items'] as List)
        .cast<Map>();
    expect(tan.firstWhere((i) => i['id'] == 'bicycle')['rental'], isTrue);
    expect(tan.firstWhere((i) => i['id'] == 'eggs').containsKey('rental'), isFalse);
  });

  test('🍱 trays bought before this update come back into your stock, once', () async {
    final store = MemoryKeyValue();
    await store.write(
      'profile',
      jsonEncode({
        'name': 'Tester',
        'wallet': 40,
        'wallet_day': '2026-12-02',
        'haggles': [
          {'stall': 'rosnah', 'item': 'tray', 'result': 'deal', 'deal': 60, 'stars': 1, 'qty': 1, 'day': '2026-11-27'},
          {'stall': 'rosnah', 'item': 'tray', 'result': 'deal', 'deal': 55, 'stars': 1, 'qty': 1, 'day': '2026-11-20'},
        ],
      }),
    );
    final c = Clock();
    var g = Game(content: content, store: store, random: math.Random(1), surprises: false, now: c.call);
    await g.load();
    expect(g.progress.stock.single['cost'], 60, reason: 'only since the wallet came in');
    await store.write('profile', g.exportProfile());
    g = Game(content: content, store: store, random: math.Random(1), surprises: false, now: c.call);
    await g.load();
    expect(g.progress.stock.length, 1, reason: 'once');
  });

  test('👛 take money out of the jar, back into the wallet', () async {
    final (g, _) = await newGame();
    await g.saveToJar(25);
    expect(g.progress.wallet, 35);
    final r = await g.takeFromJar(10);
    expect(r['taken'], 10);
    expect(g.progress.wallet, 45);
    expect(g.progress.jar, 15);
    final all = await g.takeFromJar(999);
    expect(all['taken'], 15);
    expect(g.progress.jar, 0);
    await expectLater(g.takeFromJar(5), throwsA(isA<GameError>()));
  });

  test('💰 the morning says what you earned the last day you played, and where from', () async {
    final (g, c) = await newGame();
    expect(g.me().containsKey('earned_last'), isFalse);
    final (stall, item) = ('boy', 'yoyo');
    await (() async {
      final r = await g.start(stall, item, 'none');
      await g.move(r['id'] as String, move: 'buy');
    })();
    final s = await g.shopStart();
    final sold = await g.shopMove(s['id'] as String, take: true);
    final got = (sold['price'] as num).toDouble();
    expect(g.me().containsKey('earned_last'), isFalse, reason: 'today is not "last time"');
    c.nextDay();
    final e = g.me()['earned_last'] as Map;
    expect((e['by'] as Map)['stall'], got);
    expect(e['total'] as num, greaterThanOrEqualTo(got));
  });
}
