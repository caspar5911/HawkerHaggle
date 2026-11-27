// 😄/😤 A stallholder's mood of the day, and 📦 the mystery box.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/sfx.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  DateTime t = DateTime(2026, 12, 2, 10);
  DateTime call() => t;
  void plusDays(int n) => t = DateTime(t.year, t.month, t.day + n, 10);
}

Future<(Game, Clock)> newGame({bool surprises = true, int seed = 3}) async {
  final c = Clock();
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    random: math.Random(seed),
    surprises: surprises,
    unlockAll: true,
    walletOn: true,
    now: c.call,
  );
  await g.load();
  g.me();
  return (g, c);
}

Future<void> warmUp(Game g) async {
  final w = await g.start('boy', 'yoyo', 'none');
  await g.move(w['id'] as String, move: 'buy');
}

void main() {
  setUp(() => Sfx.available = false);
  final stallIds = [for (final s in (content['stalls'] as List).cast<Map>()) '${s['id']}'];

  group('😄/😤 mood of the day', () {
    test('the same all day, changes from day to day, a stall or two a day; none without surprises', () async {
      final (g, c) = await newGame();
      var happy = 0, grumpy = 0, n = 0;
      for (var d = 0; d < 120; d++, c.plusDays(1)) {
        for (final st in stallIds) {
          final m = g.moodOfDay(st);
          c.t = DateTime(c.t.year, c.t.month, c.t.day, 22);
          expect(g.moodOfDay(st), m, reason: 'the same all day');
          c.t = DateTime(c.t.year, c.t.month, c.t.day, 10);
          if (m == 'happy') happy++;
          if (m == 'grumpy') grumpy++;
          n++;
        }
      }
      expect(happy / n, inInclusiveRange(0.06, 0.14));
      expect(grumpy / n, inInclusiveRange(0.04, 0.12));
      final (quiet, _) = await newGame(surprises: false);
      for (final st in stallIds) {
        expect(quiet.moodOfDay(st), '');
      }
    });

    test(
      'happy: warmer and more patient; grumpy: cooler and less patient; shown in the market and the haggle',
      () async {
        final views = <String, Map>{};
        for (final mood in ['', 'happy', 'grumpy']) {
          final (g, _) = await newGame(surprises: false);
          await warmUp(g);
          g.moodOverride = mood;
          final r = await g.start('mei', 'durian', 'none');
          views[mood] = r;
          if (mood.isNotEmpty) {
            expect(r['mood_today'], mood);
            expect('${r['surprise_note']}', contains(mood == 'happy' ? '😄' : '😤'));
            final card = (g.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == 'mei');
            expect(card['mood_today'], mood);
          } else {
            expect(r.containsKey('mood_today'), isFalse);
          }
        }
        num mood(String m) => views[m]!['mood'] as num;
        num patience(String m) => views[m]!['patience'] as num;
        expect(mood('happy'), greaterThan(mood('')));
        expect(mood('grumpy'), lessThan(mood('')));
        expect(patience('happy'), greaterThan(patience('')));
        expect(patience('grumpy'), lessThan(patience('')));
      },
    );

    test('never on your very first haggle (that one is always a friendly win)', () async {
      for (var d = 0; d < 60; d++) {
        final (g, c) = await newGame();
        c.plusDays(d);
        final st = stallIds.firstWhere((s) => g.moodOfDay(s).isNotEmpty, orElse: () => '');
        if (st.isEmpty || st == 'tan') continue;
        final items = ((content['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == st)['items'] as List);
        final r = await g.start(st, '${(items.first as Map)['id']}', 'none');
        expect(r.containsKey('mood_today'), isFalse);
        return;
      }
      fail('no mood day found');
    });
  });

  group('📦 the mystery box', () {
    Future<(Game, Clock, ({String stall, Map box, Map cheap, Map dear}))> mysteryDay({int seed = 3}) async {
      final (g, c) = await newGame(surprises: false, seed: seed);
      for (var d = 0; d < 30; d++, c.plusDays(1)) {
        final m = g.mysteryToday();
        if (m != null) return (g, c, m);
      }
      throw StateError('no mystery day in a month');
    }

    test('one day in three, at one stall (never Ah Ma Tan\'s), priced like its cheaper thing', () async {
      final (g, c) = await newGame(surprises: false);
      var days = 0;
      final where = <String>{};
      for (var d = 0; d < 300; d++, c.plusDays(1)) {
        final m = g.mysteryToday();
        if (m == null) continue;
        days++;
        where.add(m.stall);
        expect(m.stall, isNot('tan'));
        expect(m.box['ask'], m.cheap['ask']);
        expect(m.box['floor'], m.cheap['floor']);
        expect((m.dear['fair'] as num) >= (m.cheap['fair'] as num), isTrue);
        final card = (g.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == m.stall);
        expect((card['items'] as List).cast<Map>().where((i) => i['mystery'] == true).length, 1);
      }
      expect(days / 300, inInclusiveRange(0.25, 0.42));
      expect(where.length, greaterThan(6), reason: 'it moves around the market');
    });

    test(
      'buy it: you open it, what was inside goes into your stock (the better one about 1 time in 3); once a day',
      () async {
        var dear = 0, n = 0;
        for (var seed = 0; seed < 45; seed++) {
          final (g, _, m) = await mysteryDay(seed: seed);
          g.progress.receive(200);
          final r = await g.start(m.stall, 'mystery', 'none');
          expect(r['ask'], m.cheap['ask']);
          final done = await g.move(r['id'] as String, move: 'buy');
          expect(done['result'], 'deal');
          final notes = '${done['notes'] ?? ''} ${done['extra'] ?? ''} $done';
          expect(notes, contains('📦 You open the box'));
          final stock = g.progress.stock.map((s) => '${s['key']}').toList();
          final gotDear = stock.contains('${m.stall}/${m.dear['id']}');
          final gotCheap = stock.contains('${m.stall}/${m.cheap['id']}');
          expect(gotDear || gotCheap, isTrue, reason: 'what was inside is in your stock: $stock');
          expect(stock.where((k) => k.endsWith('/mystery')), isEmpty, reason: 'not the box itself');
          if (gotDear && m.dear['id'] != m.cheap['id']) dear++;
          n++;
          // once a day
          final card = (g.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == m.stall);
          expect((card['items'] as List).cast<Map>().firstWhere((i) => i['mystery'] == true)['sold_out'], true);
          await expectLater(g.start(m.stall, 'mystery', 'none'), throwsA(isA<GameError>()));
          // (on a day without one, or at another stall: a kind no)
          final other = stallIds.firstWhere((s) => s != m.stall && s != 'tan');
          await expectLater(g.start(other, 'mystery', 'none'), throwsA(isA<GameError>()));
          }
        expect(dear / n, inInclusiveRange(0.15, 0.55));
      },
    );
  });
}
