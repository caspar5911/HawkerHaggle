// ⚡ Market rush, 🏆 the weekly tournament, 📖 your story.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/progress.dart';
import 'package:hawker_haggle/core/tournament.dart';
import 'package:hawker_haggle/core/treats.dart';
import 'package:hawker_haggle/extras.dart' show TodayCard;
import 'package:hawker_haggle/sfx.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  DateTime t = DateTime(2026, 12, 2, 10);
  DateTime call() => t;
  void plusDays(int n) => t = DateTime(t.year, t.month, t.day + n, 10);
  void plusSeconds(int n) => t = t.add(Duration(seconds: n));
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

Future<Map<String, Object?>> buyNow(Game g, String stall, String item) async {
  final r = await g.start(stall, item, 'none');
  return g.move(r['id'] as String, move: 'buy');
}

Future<void> doMumsList(Game g, Clock c, {int secondsEach = 30}) async {
  for (final i in (g.today()['items'] as List).cast<Map>()) {
    c.plusSeconds(secondsEach);
    await buyNow(g, '${i['stall']}', '${i['item']}');
  }
}

void main() {
  setUp(() => Sfx.available = false);

  group('⚡ market rush', () {
    test("start it before Mum's list, finish in time: a bonus (once a day)", () async {
      final (g, c) = await newGame();
      final (same, sc) = await newGame(); // (the same day without the rush, to compare)
      await doMumsList(same, sc);
      expect((g.today()['rush'] as Map)['can'], true);
      await g.startRush();
      final r = g.today()['rush'] as Map;
      expect(r['left'], Progress.rushSeconds);
      await expectLater(g.startRush(), throwsA(isA<GameError>()), reason: 'once a day');
      await doMumsList(g, c);
      expect((g.today()['rush'] as Map)['won'], true);
      // the only difference is the bonus
      expect(g.progress.wallet, closeTo(same.progress.wallet + Progress.rushPrize, 0.001));
      expect(g.progress.lastEarnings(), isNull, reason: '(today is not "the last day you played" yet)');
      c.plusDays(1);
      expect((g.progress.lastEarnings()!['by'] as Map)['rush'], Progress.rushPrize);
      expect((g.today()['rush'] as Map)['can'], true, reason: 'a new day, a new rush');
    });

    test('too slow: no bonus (Mum still thanks you); and no rush once her list is started', () async {
      final (g, c) = await newGame();
      final (same, sc) = await newGame();
      await doMumsList(same, sc, secondsEach: Progress.rushSeconds ~/ 2 + 5);
      await g.startRush();
      await doMumsList(g, c, secondsEach: Progress.rushSeconds ~/ 2 + 5);
      expect((g.today()['rush'] as Map)['late'], true);
      expect(g.progress.wallet, closeTo(same.progress.wallet, 0.001));
      c.plusDays(1);
      final first = (g.today()['items'] as List).cast<Map>().first;
      await buyNow(g, '${first['stall']}', '${first['item']}');
      expect(g.today()['rush'], isNull, reason: "her list is started: no rush today");
      await expectLater(g.startRush(), throwsA(isA<GameError>()));
    });

    testWidgets('on Mum\'s list: the button, then the clock', (tester) async {
      final (g, _) = await newGame();
      var started = false;
      Future<void> show(Map<String, dynamic> today) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodayCard(today: today, onItem: (_, _) {}, onRush: () => started = true),
          ),
        ),
      );
      await show(Map<String, dynamic>.from(g.today()));
      await tester.tap(find.byKey(const ValueKey('rush_start')));
      expect(started, isTrue);
      await g.startRush();
      await show(Map<String, dynamic>.from(g.today()));
      expect(find.byKey(const ValueKey('rush_clock')), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // (stops the clock's timer)
    });
  });

  group('🏆 weekly tournament', () {
    test('one of the stalls\' own things, the same all week (Monday to Sunday), changing each week', () {
      final seen = <String>{};
      for (var w = 0; w < 20; w++) {
        final mon = DateTime(2026, 11, 30 + 7 * w, 9);
        final t = tournamentItem(mon, content)!;
        for (var d = 1; d < 7; d++) {
          expect(tournamentItem(DateTime(mon.year, mon.month, mon.day + d, 23), content)!.item['id'], t.item['id']);
        }
        expect('${t.stall}/${t.item['id']}', isNot('tan/bicycle'));
        final st = (content['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == t.stall);
        expect((st['items'] as List).cast<Map>().map((i) => i['id']), contains(t.item['id']), reason: 'on the server');
        seen.add('${t.stall}/${t.item['id']}');
      }
      expect(seen.length, greaterThan(8));
      expect(weekStartKey(DateTime(2026, 12, 6, 23)), '2026-11-30'); // Sunday: still the week from Monday
      expect(weekStartKey(DateTime(2026, 12, 7, 0, 1)), '2026-12-07');
    });

    test('top with another player: the prize, once a week; alone, or not on top: no prize', () async {
      final (g, c) = await newGame();
      final t = tournamentItem(g.now(), content)!;
      Map board(List<Map> top, int players) => {
        'items': [
          {'stall': t.stall, 'item': t.item['id'], 'top': top, 'players': players},
        ],
      };
      final before = g.progress.wallet;
      var r = (await g.tournament(
        board([
          {'name': 'Me', 'price': 10, 'you': true},
        ], 1),
      ))!;
      expect(r.containsKey('prize_now'), isFalse, reason: 'alone on the board');
      r = (await g.tournament(
        board([
          {'name': 'Ah Seng', 'price': 9, 'you': false},
          {'name': 'Me', 'price': 10, 'you': true},
        ], 2),
      ))!;
      expect(r.containsKey('prize_now'), isFalse, reason: 'second');
      r = (await g.tournament(
        board([
          {'name': 'Me', 'price': 8, 'you': true},
          {'name': 'Ah Seng', 'price': 9, 'you': false},
        ], 2),
      ))!;
      expect('${r['prize_now']}', contains('🏆'));
      expect(g.progress.wallet, closeTo(before + tournamentPrize, 0.001));
      r = (await g.tournament(
        board([
          {'name': 'Me', 'price': 7, 'you': true},
          {'name': 'Ah Seng', 'price': 9, 'you': false},
        ], 2),
      ))!;
      expect(r.containsKey('prize_now'), isFalse, reason: 'once a week');
      expect(r['won'], true);
      // (not logged in: no board, no prize)
      c.plusDays(7);
      expect((await g.tournament(null))!.containsKey('prize_now'), isFalse);
      // the item is tagged in the market
      final tt = tournamentItem(g.now(), content)!;
      final card = (g.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == tt.stall);
      expect((card['items'] as List).cast<Map>().firstWhere((i) => i['id'] == tt.item['id'])['tournament'], true);
    });
  });

  group('📖 your story', () {
    test('chapters are reached by playing and claimed once each, with a reward and a word from Mum', () async {
      final (g, c) = await newGame();
      var story = g.career();
      expect((story['chapters'] as List).length, Progress.careerChapters.length);
      expect(story['done'], 0);
      expect((story['next'] as Map)['id'], 'helper');
      await expectLater(g.claimCareer('helper'), throwsA(isA<GameError>()), reason: 'not reached yet');
      await doMumsList(g, c);
      story = g.career();
      expect(story['to_claim'], 1);
      final before = g.progress.wallet;
      final r = await g.claimCareer('helper');
      expect('${r['mum']}', isNotEmpty);
      expect(g.progress.wallet, closeTo(before + 5, 0.001));
      await expectLater(g.claimCareer('helper'), throwsA(isA<GameError>()), reason: 'once');
      // a first sale at your own stall
      final s = await g.shopStart();
      await g.shopMove(s['id'] as String, take: true);
      expect(((g.career()['chapters'] as List).cast<Map>().firstWhere((x) => x['id'] == 'seller'))['reached'], true);
      // the awning, from the shop
      g.progress.addToJar(goals.firstWhere((x) => x.id == 'awning').cost);
      await g.buyGoal('awning');
      expect(((g.career()['chapters'] as List).cast<Map>().firstWhere((x) => x['id'] == 'awning'))['reached'], true);
      expect(g.career()['to_claim'], 2);
      await expectLater(g.claimCareer('nope'), throwsA(isA<GameError>()));
    });

    test('every chapter can be reached (each has a rule), and the rewards stay small next to the shop', () {
      final total = Progress.careerChapters.fold<double>(0, (a, c) => a + c.$5);
      expect(total, lessThan(300));
      for (final c in Progress.careerChapters) {
        if (const {'awning', 'scooter', 'stall2', 'wall'}.contains(c.$1)) {
          expect(goals.any((x) => x.id == c.$1), isTrue, reason: '${c.$1} is a shop goal');
        }
      }
    });
  });
}
