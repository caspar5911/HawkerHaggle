// The savings jar and goals, freebies, dilemmas and the quote book.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/treats.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

Future<Game> newGame({bool surprises = false, int seed = 9}) async {
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    random: math.Random(seed),
    unlockAll: true,
    surprises: surprises,
    now: () => DateTime(2026, 11, 26, 10), // not a festival week
  );
  await g.load();
  return g;
}

Future<Map> buy(Game g, String stall, String item, {String? text, String surprise = 'none'}) async {
  var r = await g.start(stall, item, surprise);
  final id = r['id'] as String;
  if (text != null) {
    r = await g.move(id, text: text);
    if (r['done'] != true) r = await g.move(id, text: '\$${r['ask']} ok I take');
    if (r['pending'] != null && r['done'] != true) r = await g.move(id, move: 'confirm');
  }
  for (var i = 0; i < 5 && r['done'] != true; i++) {
    r = await g.move(id, move: 'buy');
  }
  return r;
}

void main() {
  test('the jar fills with what you bargain off; paying the asking price saves nothing; goals spend it', () async {
    final g = await newGame();
    expect(g.jar()['jar'], 0);
    final full = await buy(g, 'mei', 'durian'); // at the asking price
    expect(full['result'], 'deal');
    expect(g.jar()['jar'], 0);
    final cheap = await buy(g, 'mei', 'durian', text: r'I only have $18');
    final kept = 32 - (cheap['deal'] as num);
    expect(g.jar()['jar'], closeTo(kept, 0.001));
    expect((cheap['notes'] as List).cast<String>().any((n) => n.contains('into your savings jar')), isTrue);
    await expectLater(g.buyGoal('scooter'), throwsA(isA<GameError>())); // not enough yet
    while ((g.jar()['jar'] as num) < 30) {
      await buy(g, 'mei', 'durian', text: r'I only have $18');
    }
    final r = await g.buyGoal('cake');
    expect('${r['note']}', contains('birthday cake'));
    expect(r['new_stickers'], contains('saver'));
    await expectLater(g.buyGoal('cake'), throwsA(isA<GameError>())); // only once
    expect((g.jar()['goals'] as List).cast<Map>().firstWhere((x) => x['id'] == 'cake')['owned'], isTrue);
  });

  test('your stall profit goes in the jar; the awning can be bought', () async {
    final g = await newGame();
    var s = await g.shopStart('scarf');
    s = await g.shopMove(s['id'] as String, take: true);
    final profit = (s['profit'] as num).toDouble();
    expect(g.jar()['jar'], closeTo(math.max(0, profit), 0.001));
    g.progress.addToJar(500);
    await g.buyGoal('awning');
    expect(g.progress.owns('awning'), isTrue);
  });

  test('freebies: only with surprises on, into your stock for free, guaranteed after a dry spell', () async {
    final quiet = await newGame();
    for (var i = 0; i < 10; i++) {
      await buy(quiet, 'mei', 'mango', text: r'wah so nice, $13 can?');
    }
    expect(quiet.progress.stock.where((x) => '${x['key']}'.startsWith('free:')), isEmpty);

    final g = await newGame(surprises: true, seed: 3);
    var got = 0, deals = 0, longestDry = 0, dry = 0;
    for (var i = 0; i < 40; i++) {
      final r = await buy(g, 'mei', 'mango', text: r'I only have $11');
      if (r['result'] != 'deal') continue;
      deals++;
      final free = (r['notes'] as List).cast<String>().where((n) => n.startsWith('🎁')).toList();
      if (free.isNotEmpty) {
        got++;
        dry = 0;
        expect(free.single, contains('lucky orange'));
      } else if ((r['stars'] as num) >= 2) {
        dry++;
        longestDry = math.max(longestDry, dry);
      }
    }
    expect(got, greaterThan(0));
    expect(longestDry, lessThanOrEqualTo(3)); // the pity floor
    expect(g.stickers().firstWhere((s) => s['id'] == 'lucky')['earned'], isNotNull);
    final free = g.progress.stock.where((x) => x['key'] == 'free:mei').toList();
    expect(free, isNotEmpty);
    expect(free.first['cost'], 0);
    expect(deals, greaterThan(20));
  });

  test('dilemmas: offered now and then to friends; helping costs the jar and grows friendship', () async {
    final g = await newGame(surprises: true, seed: 5);
    g.progress.addToJar(20);
    for (var i = 0; i < 3; i++) {
      await buy(g, 'siti', 'scarf');
    }
    expect(g.progress.hearts('siti'), greaterThanOrEqualTo(1));
    Map? offered;
    String? id;
    for (var i = 0; i < 40 && offered == null; i++) {
      final r = await g.start('siti', 'kueh', 'none');
      if (r['dilemma'] is Map) {
        offered = r['dilemma'] as Map;
        id = r['id'] as String;
      }
    }
    expect(offered, isNotNull);
    expect(offered!['text'], contains('Kak Siti'));
    expect(offered['can'], isTrue);
    expect(RegExp(r'\$|\d').hasMatch('${offered['text']}'), isFalse); // the cost is on the button only
    final before = g.progress.points('siti');
    final jarBefore = g.progress.jar;
    final note = await g.answerDilemma(id!, help: true);
    expect(note, contains('touched'));
    expect(g.progress.jar, closeTo(jarBefore - (offered['cost'] as num), 0.001));
    expect(g.progress.points('siti'), greaterThanOrEqualTo(before));
    await expectLater(g.answerDilemma(id, help: true), throwsA(isA<GameError>())); // once
    final quiet = await newGame(); // without surprises: never
    for (var i = 0; i < 3; i++) {
      await buy(quiet, 'siti', 'scarf');
    }
    for (var i = 0; i < 30; i++) {
      expect((await quiet.start('siti', 'kueh', 'none'))['dilemma'], isNull);
    }
    expect(dilemmas.keys.toSet(), (content['stalls'] as List).map((s) => s['id']).toSet()); // one for everyone
  });

  test('quote book: saved once, capped, newest first, removable; a sticker at five', () async {
    final g = await newGame();
    expect(await g.saveQuote('mei', 'Aiyo, you so cute, I give you lah!'), isTrue);
    expect(await g.saveQuote('mei', 'Aiyo, you so cute, I give you lah!'), isFalse); // no duplicates
    await expectLater(g.saveQuote('nobody', 'x'), throwsA(isA<GameError>()));
    for (var i = 0; i < 60; i++) {
      await g.saveQuote('lim', 'Line $i ${'x' * 300}');
    }
    final q = g.quotes();
    expect(q, hasLength(quotesKept));
    expect('${q.first['text']}', startsWith('Line 59'));
    expect('${q.first['text']}'.length, quoteMaxChars);
    expect(q.first['name'], 'Uncle Lim');
    expect(g.stickers().firstWhere((s) => s['id'] == 'quotes5')['earned'], isNotNull);
    await g.removeQuote('${q.first['text']}');
    expect(g.quotes(), hasLength(quotesKept - 1));
  });

  test('going firm too early gets a higher "best price", and a hint afterwards', () async {
    final g = await newGame();
    var r = await g.start('mei', 'mango', 'none'); // her lowest is $10
    final id = r['id'] as String;
    r = await g.move(id, text: r'I only have $8');
    expect(r['event'], 'budget_best');
    expect(r['ask'] as num, greaterThan(10.6)); // not her real lowest: that has to be earned
    r = await g.move(id, text: r'$10 can?');
    expect(r['event'], 'final'); // and it's final
    r = await g.move(id, move: 'buy');
    expect('${r['closeness']}', contains('went firm early'));
  });

  group('reading the stallholder', () {
    List<String> tells(Map r) => (r['tells'] as List).cast<String>();

    test('a kind word warms them; a firm price too early gets their "best", which they hold', () async {
      final g = await newGame();
      var r = await g.start('mei', 'mango', 'none');
      final id = r['id'] as String;
      expect(tells(r), isEmpty);
      r = await g.move(id, text: 'wah so nice');
      expect(tells(r), contains('😊 Auntie Mei is warming to you.'));
      r = await g.move(id, text: r'I only have $8');
      expect(tells(r).first, "🧱 Auntie Mei won't go any lower this time.");
      r = await g.move(id, text: 'you are so stupid');
      expect(tells(r), contains('😠 That put Auntie Mei off.'));
    });

    test('bargaining well: they seem ready to settle, and then a firm price at their lowest is a yes', () async {
      final g = await newGame();
      var r = await g.start('mei', 'mango', 'none'); // her lowest is $10
      final id = r['id'] as String;
      final seen = <String>[];
      for (final t in ['wah so nice', r'$8.50 can?', 'I come every week', 'so fresh, very good', r'$9 can?']) {
        r = await g.move(id, text: t);
        seen.addAll(tells(r));
      }
      expect(seen, contains('🤝 Auntie Mei seems ready to settle.'));
      r = await g.move(id, text: r'$10 can?');
      if (r['pending'] == null) r = await g.move(id, text: r'$10 can?');
      expect(r['pending'], 10);
      expect(tells(r), isEmpty); // nothing to read while a deal waits
    });

    test('tells never carry a number, and say little: at most two a move', () async {
      final g = await newGame(surprises: true);
      final rnd = math.Random(4);
      const says = [
        'hello',
        'wah so nice',
        'I come every week',
        r'$5',
        r'$9 can?',
        r'$12 lah',
        'cheaper can?',
        'stupid',
      ];
      for (var i = 0; i < 60; i++) {
        var r = await g.start('lim', 'pomfret', 'none');
        for (var k = 0; k < 8 && r['done'] != true && r['pending'] == null; k++) {
          r = await g.move(r['id'] as String, text: says[rnd.nextInt(says.length)]);
          expect(tells(r).length, lessThanOrEqualTo(2));
          for (final t in tells(r)) {
            expect(RegExp(r'\d|\$').hasMatch(t), isFalse, reason: t);
          }
        }
      }
    });
  });

  group('twists', () {
    Future<(Game, Map, String)> toTwist(Game g) async {
      for (var tries = 0; tries < 30; tries++) {
        var r = await g.start('mei', 'durian', 'none');
        final id = r['id'] as String;
        for (var i = 0; i < 3 && r['done'] != true; i++) {
          r = await g.move(id, text: 'hello auntie, nice day');
        }
        if (r['twist'] is Map) return (g, r, id);
      }
      throw StateError('no twist');
    }

    test('a few moves in, a twist with a choice; the choice changes only the mood', () async {
      final g = await newGame(surprises: true)
        ..twistChance = 100;
      final (_, r, id) = await toTwist(g);
      final t = r['twist'] as Map;
      expect('${t['text']}', anyOf(contains('Auntie Mei'), contains('durian')));
      expect(RegExp(r'\$|\d').hasMatch('${t['text']}'), isFalse);
      final ask = r['ask'];
      final mood = (r['mood'] as num).toDouble();
      final reaction = await g.answerTwist(id, 0); // the kind choice
      expect(reaction, isNotEmpty);
      final after = await g.move(id, text: 'so how much now?');
      expect((after['mood'] as num).toDouble(), greaterThan(mood - 0.5)); // warmer (the next move moves it too)
      expect(after['twist'], isNull); // once a haggle
      expect(after['ask'], lessThanOrEqualTo(ask as num)); // never a higher price
      await expectLater(g.answerTwist(id, 0), throwsA(isA<GameError>()));
    });

    test('an unanswered twist passes with the next move; none without surprises', () async {
      final g = await newGame(surprises: true)
        ..twistChance = 100;
      final (_, _, id) = await toTwist(g);
      await g.move(id, text: 'ok what is your best price');
      await expectLater(g.answerTwist(id, 0), throwsA(isA<GameError>()));
      final quiet = await newGame()
        ..twistChance = 100;
      for (var i = 0; i < 10; i++) {
        var r = await quiet.start('mei', 'durian', 'none');
        for (var k = 0; k < 4 && r['done'] != true; k++) {
          r = await quiet.move(r['id'] as String, text: 'hello auntie');
          expect(r['twist'], isNull);
        }
      }
    });

    test('every twist has words for the stallholder and no numbers', () {
      for (final t in twists) {
        expect(t.options, isNotEmpty);
        for (final o in t.options) {
          expect(RegExp(r'\d|\$').hasMatch('${t.text}${t.ai}${o.$1}${o.$3}${o.$4}'), isFalse, reason: t.id);
          expect(o.$2.abs(), lessThanOrEqualTo(1.5));
        }
      }
    });
  });
}
