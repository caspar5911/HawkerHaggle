// 🗓️ This week's special: a third thing at every stall, a different one each week.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/shop.dart';
import 'package:hawker_haggle/core/specials.dart';
import 'package:hawker_haggle/sfx.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  DateTime t = DateTime(2026, 12, 2, 10); // a Wednesday
  DateTime call() => t;
  void plusDays(int n) => t = DateTime(t.year, t.month, t.day + n, 10);
}

Future<(Game, Clock)> newGame() async {
  final c = Clock();
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    random: math.Random(3),
    surprises: false,
    unlockAll: true,
    walletOn: true,
    now: c.call,
  );
  await g.load();
  g.me();
  return (g, c);
}

void main() {
  setUp(() => Sfx.available = false);
  final stalls = {for (final s in (content['stalls'] as List).cast<Map>()) '${s['id']}': s};

  test('every stall has two specials, priced like its own things, with facts and no numbers in them', () {
    expect(specials.keys.toSet(), stalls.keys.toSet());
    for (final MapEntry(key: st, value: list) in specials.entries) {
      expect(list.length, 2, reason: st);
      final own = {for (final i in (stalls[st]!['items'] as List).cast<Map>()) i['id']};
      final fairs = [for (final i in (stalls[st]!['items'] as List).cast<Map>()) (i['fair'] as num).toDouble()];
      for (final x in list) {
        final id = '${x['id']}';
        expect(own.contains(id), isFalse, reason: '$st/$id clashes with its own item');
        final fair = (x['fair'] as num).toDouble(), ask = (x['ask'] as num).toDouble();
        final floor = (x['floor'] as num).toDouble();
        expect(floor < fair && fair < ask, isTrue, reason: '$st/$id: floor < fair < ask');
        // her first price and her lowest, like on the stall's own things (give or take a little)
        final asks = [
          for (final i in (stalls[st]!['items'] as List).cast<Map>()) (i['ask'] as num) / (i['fair'] as num),
        ];
        final lows = [
          for (final i in (stalls[st]!['items'] as List).cast<Map>()) (i['floor'] as num) / (i['fair'] as num),
        ];
        expect(
          ask / fair,
          inInclusiveRange(asks.reduce(math.min) - 0.15, asks.reduce(math.max) + 0.15),
          reason: '$st/$id: her first price',
        );
        expect(
          floor / fair,
          inInclusiveRange(lows.reduce(math.min) - 0.08, lows.reduce(math.max) + 0.08),
          reason: '$st/$id: her lowest',
        );
        // (in the range of the stall's own prices, give or take)
        expect(fair, inInclusiveRange(fairs.reduce(math.min) * 0.4, fairs.reduce(math.max) * 1.6), reason: '$st/$id');
        final facts = (x['facts'] as List).cast<String>();
        expect(facts.length, greaterThanOrEqualTo(4), reason: '$st/$id');
        for (final f in facts) {
          expect(RegExp(r'\d').hasMatch(f), isFalse, reason: '$st/$id: a number in "$f"');
        }
        expect(RegExp(r'\d').hasMatch('${x['name']}'), isFalse, reason: '$st/$id: a number in its name');
        expect(kindOf('$st/$id'), isNot('other'), reason: '$st/$id: what kind of thing');
        expect(x.containsKey('pieces'), isFalse, reason: '$st/$id: one thing, not pieces');
      }
    }
  });

  test('the special changes each week (Monday), and stays the same all week', () {
    final mon = DateTime(2026, 11, 30, 8);
    expect(mon.weekday, DateTime.monday);
    for (final st in specials.keys) {
      final a = specialFor(st, mon)!['id'];
      for (var d = 0; d < 7; d++) {
        expect(specialFor(st, DateTime(2026, 11, 30 + d, 23))!['id'], a, reason: '$st day $d');
      }
      expect(specialFor(st, DateTime(2026, 12, 7, 0, 5))!['id'], isNot(a), reason: '$st: next week');
      expect(specialFor(st, DateTime(2026, 12, 14, 9))!['id'], a, reason: '$st: and back the week after');
    }
    // (not all stalls show the same one of their two in the same week)
    final firsts = {for (final st in specials.keys) specials[st]!.indexWhere((x) => x == specialFor(st, mon))};
    expect(firsts, {0, 1});
  });

  test('in the market: at its stall, marked; Mum\'s list never has it', () async {
    final (g, c) = await newGame();
    final view = g.stalls();
    for (final s in (view['stalls'] as List).cast<Map>()) {
      final items = (s['items'] as List).cast<Map>();
      final sp = items.where((i) => i['special'] == true).toList();
      expect(sp.length, 1, reason: '${s['id']}');
      expect(sp.single['id'], specialFor('${s['id']}', g.now())!['id']);
    }
    final days = <String>{};
    for (var d = 0; d < 21; d++, c.plusDays(1)) {
      final today = g.progress.today();
      days.add('${today['date'] ?? g.now().day}');
      for (final i in (today['items'] as List).cast<Map>()) {
        expect(anySpecial('${i['stall']}', '${i['item']}'), isNull);
      }
    }
    expect(days.length, 21, reason: 'three weeks of lists');
  });

  test('haggle for it, buy it, it goes into your stock; last week\'s special is gone (said kindly)', () async {
    final (g, c) = await newGame();
    g.progress.receive(200);
    final x = specialFor('lim', g.now())!;
    final r = await g.start('lim', '${x['id']}', 'none');
    expect(r['ask'], x['ask']);
    final done = await g.move(r['id'] as String, move: 'buy');
    expect(done['done'], true);
    expect(g.progress.stock.any((s) => s['key'] == 'lim/${x['id']}'), isTrue);
    expect(g.history().first['item'], x['id']);
    // a customer who loves it pays more for it (a crab is a premium thing)
    expect(kindOf('lim/${x['id']}'), isNot('other'));
    // next week it's the other one; this one can't be haggled for
    c.plusDays(7);
    expect(specialFor('lim', g.now())!['id'], isNot(x['id']));
    await expectLater(g.start('lim', '${x['id']}', 'none'), throwsA(isA<GameError>()));
    // (what you bought is still in your stock, and still sells)
    expect(g.progress.stock.any((s) => s['key'] == 'lim/${x['id']}'), isTrue);
  });
}
