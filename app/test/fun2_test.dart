// Buy low, sell high; how close you got; how you haggled last time; soft spots; persuasion moments.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/reader.dart';
import 'package:hawker_haggle/core/softspots.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

Future<Game> newGame({AiClient? ai}) async {
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    ai: ai,
    random: math.Random(9),
    unlockAll: true,
    surprises: false,
  );
  await g.load();
  return g;
}

/// A deal at the asking price (or lower with "I only have").
Future<Map> buy(Game g, String stall, String item, {String? text}) async {
  var r = await g.start(stall, item, 'none');
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

/// A pretend AI: stallholder lines without prices, a pitch judge with a set score, rules for reading.
class FakeAi extends AiClient {
  FakeAi({this.score = 2, this.judgeRaw})
    : super(
        const AiConfig(endpoint: 'https://ai.example/v1', model: 'm'),
        client: MockClient((_) async => http.Response('', 500)),
      );
  int score;
  String? judgeRaw;
  final notes = <String>[];
  int judged = 0, reasons = 0;

  @override
  Future<Heard> understand(
    String text, {
    List<Map> history = const [],
    double? ask,
    String item = '',
    String name = 'Stallholder',
    double? pending,
    double? lastOffer,
    int qty = 1,
  }) async => heardByRules(text);

  @override
  Future<String?> say({
    required Map stall,
    required Map item,
    required String event,
    required Map<String, double?> numbers,
    List<Map> history = const [],
    String? heard,
    Iterable<num> alsoOk = const [],
    String unclear = '',
    double? budget,
    double? patience,
    String also = '',
    String note = '',
  }) async {
    notes.add(note);
    return 'Hmm, okay lah.';
  }

  @override
  Future<int?> judgePitch({
    required Map stall,
    required Map item,
    required String pitch,
    bool unprompted = false,
  }) async {
    judged++;
    if (unprompted) reasons++;
    return score;
  }

  @override
  Future<bool?> callBack({
    required Map stall,
    required Map item,
    List<Map> history = const [],
    required double ask,
    double? lastOffer,
  }) async => false;
}

void main() {
  group('buy low, sell high', () {
    test('deals become stock at the price paid; a qty-2 deal adds two; a rental is not resold (a tray is)', () async {
      final g = await newGame();
      expect(g.progress.stock, isEmpty);
      await buy(g, 'mei', 'mango');
      expect(g.progress.stock, hasLength(1));
      expect(g.progress.stock.single['cost'], 18); // the asking price, paid in full
      await buy(g, 'tan', 'bicycle');
      expect(g.progress.stock, hasLength(1)); // a day's rental: given back by 6pm
      await buy(g, 'rosnah', 'tray');
      expect(g.progress.stock, hasLength(2)); // a nasi lemak tray can be sold again (since test 56)
      g.progress.p['stock'] = [...g.progress.stock.take(1)]; // (back to the mango, for the counts below)
      expect(g.progress.stock, hasLength(1));
      var r = await g.start('raj', 'case', 'none');
      r = await g.move(r['id'] as String, text: 'I buy two');
      for (var i = 0; i < 5 && r['done'] != true; i++) {
        r = await g.move(r['id'] as String, move: 'buy');
      }
      expect(r['qty'], 2);
      expect(g.progress.stock, hasLength(3));
      for (var i = 0; i < 12; i++) {
        await buy(g, 'lim', 'pomfret');
      }
      expect(g.progress.stock, hasLength(10)); // capped, oldest go first
      expect(g.progress.stock.first['key'], 'lim/pomfret');
    });

    test(
      'the shop sells your stock first; a sale removes it, a walk-away keeps it; empty stock is wholesale',
      () async {
        final g = await newGame();
        final cheap = await buy(g, 'mei', 'mango', text: r'I only have $9');
        final paid = (cheap['deal'] as num).toDouble();
        var s = await g.shopStart();
        expect((s['product'] as Map)['id'], 'stock:mei/mango');
        expect((s['product'] as Map)['cost'], paid); // your haggle sets your profit
        expect((s['product'] as Map)['from'], 'Auntie Mei');
        expect(s['stock'], 1);
        // asking far too much: they walk, and the mangoes stay in stock
        for (var i = 0; i < 6 && s['done'] != true; i++) {
          s = await g.shopMove(s['id'] as String, ask: 500);
        }
        expect(s['result'], 'walked');
        expect(g.progress.stock, hasLength(1));
        s = await g.shopStart();
        s = await g.shopMove(s['id'] as String, take: true);
        expect(s['result'], 'sold');
        expect(s['profit'], closeTo((s['price'] as num) - paid, 1e-9));
        expect(g.progress.stock, isEmpty);
        s = await g.shopStart();
        expect('${(s['product'] as Map)['id']}', isNot(startsWith('stock:')));
        expect((s['product'] as Map)['from'], isNull);
      },
    );
  });

  test('how close you got: in words only, and agreeing with the stars', () async {
    final g = await newGame();
    final full = await buy(g, 'mei', 'durian'); // the asking price
    expect('${full['closeness']}', contains('room left'));
    for (final budget in [16, 17, 18, 19, 20]) {
      final r = await buy(g, 'mei', 'durian', text: 'I only have \$$budget');
      if (r['result'] != 'deal') continue;
      final c = '${r['closeness']}';
      expect(RegExp(r'\d|\$').hasMatch(c), isFalse, reason: c); // never a number
      if ((r['stars'] as num) >= 3) expect(c, anyOf(contains('Right at'), contains('Very close')));
    }
    final walked = await g.start('mei', 'mango', 'none');
    var w = await g.move(walked['id'] as String, move: 'walk');
    for (var i = 0; i < 5 && w['done'] != true; i++) {
      w = await g.move(walked['id'] as String, move: 'walk');
    }
    if (w['result'] != 'deal') expect(w['closeness'], isNull);
  });

  test('the stallholder remembers how you haggled last time (no numbers)', () async {
    final g = await newGame();
    expect(g.progress.howTheyHaggled('mei'), isEmpty);
    await buy(g, 'mei', 'durian');
    expect(g.progress.howTheyHaggled('mei'), contains('close to your asking price'));
    await buy(g, 'mei', 'durian', text: r'I only have $16');
    expect(g.progress.howTheyHaggled('mei'), anyOf(contains('very hard'), contains('a little, fairly')));
    for (final s in ['mei', 'lim']) {
      expect(RegExp(r'\d').hasMatch(g.progress.howTheyHaggled(s)), isFalse);
    }
  });

  group('soft spots', () {
    test('whole words only', () {
      expect(softSpots['lee']!.heardIn('Auntie do you like Cantonese opera?'), isTrue);
      expect(softSpots['lee']!.heardIn('cooperate'), isFalse); // "opera" inside a word doesn't count
      expect(softSpots['boy']!.heardIn('Watched the F1 last night'), isTrue);
      expect(softSpots['rosnah']!.heardIn('my brother is a baker'), isFalse);
      expect(softSpots['faiz']!.heardIn('You watch football?'), isTrue);
    });

    test('mentioning it warms them once a haggle, and the first time it is found for the profile', () async {
      final g = await newGame();
      expect(g.stallProfile('lim')['soft_spot'], isNull);
      final r = await g.start('lim', 'pomfret', 'none');
      final id = r['id'] as String;
      final before = (r['mood'] as num).toDouble();
      final a = await g.move(id, text: 'Uncle, you go fishing on weekends?');
      expect(a['found'], 'fishing trips');
      expect((a['mood'] as num).toDouble(), greaterThan(before));
      final moodAfter = (a['mood'] as num).toDouble();
      final b = await g.move(id, text: 'I love fishing also');
      expect(b['found'], isNull);
      expect((b['mood'] as num).toDouble() - moodAfter, lessThan(1.0)); // no second soft-spot warm-up (+1.2)
      expect(g.stallProfile('lim')['soft_spot'], 'fishing trips');
      final again = await g.start('lim', 'pomfret', 'none');
      final c = await g.move(again['id'] as String, text: 'fishing this weekend?');
      expect(c['found'], isNull); // already in the profile
    });
  });

  group('persuasion moments', () {
    test('only with the AI, about one haggle in two, never touching the dice; a good pitch warms them', () async {
      final ai = FakeAi(score: 2);
      final g = await newGame(ai: ai);
      var challenged = 0, haggles = 0;
      for (var i = 0; i < 60; i++) {
        var r = await g.start('mei', 'durian', 'none');
        final id = r['id'] as String;
        haggles++;
        r = await g.move(id, text: 'hello auntie how are you');
        r = await g.move(id, text: 'business good today?');
        if (r['challenge'] == true) {
          challenged++;
          expect(ai.notes.last, contains('challenging them'));
          final mood = (r['mood'] as num).toDouble();
          final p = await g.move(
            id,
            text:
                'Auntie, your durian is the reason my grandma smiles, story ${String.fromCharCode(97 + i % 26)}${String.fromCharCode(97 + i ~/ 26)}',
          );
          expect(p['pitch_score'], 2);
          expect(p['challenge'], isFalse);
          expect((p['mood'] as num).toDouble(), greaterThan(mood - 0.01));
          expect(ai.notes.last, contains('won you over'));
        }
      }
      expect(challenged / haggles, inInclusiveRange(0.3, 0.7));
      expect(ai.judged, challenged);
    });

    test('💬 the same pitch twice: the second time it scores nothing (and the AI is not even asked)', () async {
      final ai = FakeAi(score: 2);
      final g = await newGame(ai: ai);
      const line = 'Auntie, your durian is the reason my grandma smiles every Sunday!';
      final scores = <int>[];
      for (var i = 0; i < 60 && scores.length < 2; i++) {
        var r = await g.start('mei', 'durian', 'none');
        final id = r['id'] as String;
        r = await g.move(id, text: 'hello auntie how are you');
        r = await g.move(id, text: 'business good today?');
        if (r['challenge'] == true) {
          final before = ai.judged;
          final p = await g.move(
            id,
            text: scores.isEmpty ? line : '  AUNTIE, your durian is the reason my GRANDMA smiles every sunday ',
          );
          scores.add((p['pitch_score'] as num).toInt());
          if (scores.length == 2) expect(ai.judged, before, reason: 'a repeat is not sent to the AI');
        }
      }
      expect(scores, [2, 0]);
    });

    test(
      '💬 a reason given unasked: scored once a haggle, warms them; short or plain messages are never sent',
      () async {
        final ai = FakeAi(score: 2);
        final g = await newGame(ai: ai);
        var r = await g.start('mei', 'durian', 'none');
        final id = r['id'] as String;
        r = await g.move(id, text: 'cheaper lah auntie');
        r = await g.move(id, text: '20 can?');
        expect(ai.reasons, 0, reason: 'no reason in those');
        final mood = (r['mood'] as num).toDouble();
        r = await g.move(id, text: "Auntie, it's for my grandma's birthday, she loves your durians the most");
        expect(ai.reasons, 1);
        expect((r['mood'] as num).toDouble(), greaterThan(mood));
        expect(ai.notes.last, contains('really touched you'));
        r = await g.move(id, text: 'And my grandson also loves durian because he is just like his grandma');
        expect(ai.reasons, 1, reason: 'once a haggle');
        // (the same reason in another haggle: not again)
        final r2 = await g.start('mei', 'durian', 'none');
        await g.move(
          r2['id'] as String,
          text: "Auntie, it's for my grandma's birthday, she loves your durians the most",
        );
        expect(ai.reasons, 1);
        // (no AI: nothing is judged)
        final plain = await newGame();
        final r3 = await plain.start('mei', 'durian', 'none');
        final x = await plain.move(
          r3['id'] as String,
          text: "Auntie, it's for my grandma's birthday, she loves your durians",
        );
        expect(x.containsKey('reason'), isFalse);
      },
    );

    test('a tap lets the challenge lapse; no AI, no challenges', () async {
      final ai = FakeAi(score: 2);
      final g = await newGame(ai: ai);
      for (var i = 0; i < 40; i++) {
        var r = await g.start('mei', 'durian', 'none');
        final id = r['id'] as String;
        r = await g.move(id, text: 'hello auntie');
        r = await g.move(id, text: 'nice day');
        if (r['challenge'] == true) {
          final t = await g.move(id, pick: 0);
          expect(t['challenge'], isFalse);
          expect(ai.judged, 0);
          break;
        }
      }
      final plain = await newGame();
      for (var i = 0; i < 20; i++) {
        var r = await plain.start('mei', 'durian', 'none');
        r = await plain.move(r['id'] as String, text: 'hello auntie');
        r = await plain.move(r['id'] as String, text: 'nice day');
        expect(r['challenge'], isFalse);
      }
    });

    test('the judge: malformed answers are 0, scores are clamped, no answer is null', () async {
      Future<int?> judge(String? reply) {
        final ai = AiClient(
          const AiConfig(endpoint: 'https://ai.example/v1', model: 'm'),
          client: MockClient(
            (_) async => reply == null
                ? http.Response('down', 500)
                : http.Response(
                    jsonEncode({
                      'choices': [
                        {
                          'message': {'content': reply},
                        },
                      ],
                    }),
                    200,
                  ),
          ),
        );
        return ai.judgePitch(
          stall: content['stalls'][0] as Map,
          item: (content['stalls'][0]['items'] as List)[0] as Map,
          pitch: 'x',
        );
      }

      expect(await judge('{"score": 2, "why": "lovely"}'), 2);
      expect(await judge('{"score": 7}'), 2);
      expect(await judge('{"score": -3}'), 0);
      expect(await judge('I think it deserves a 2'), 0);
      expect(await judge('{"score": "two"}'), 0);
      expect(await judge(null), isNull);
    });
  });

  test("live co-op: a friend's move is answered knowing two friends are bargaining", () async {
    final ai = FakeAi();
    final g = await newGame(ai: ai);
    final r = await g.start('mei', 'mango', 'none');
    await g.move(r['id'] as String, text: 'auntie give my friend a good price', friend: 'Melody 99');
    expect(ai.notes.last, contains('Two friends are bargaining'));
    expect(ai.notes.last, contains('"Melody"')); // cleaned, no numbers
    await g.move(r['id'] as String, text: 'and me also lah');
    expect(ai.notes.last, isNot(contains('Two friends')));
    expect(await g.teamwork(), ['teamwork']);
    expect(await g.teamwork(), isEmpty); // once
  });
}
