// Release 47: stallholders remember your last visit and hear gossip about your hard bargains, and react when you
// keep poking them.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/progress.dart';

import 'game_ai_test.dart' show FakeModel;

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

Future<(Game, FakeModel)> aiGame(DateTime Function() now, {MemoryKeyValue? store, FakeModel? model}) async {
  final m = model ?? FakeModel(line: 'Aiyo, come come!');
  m.callBack = false;
  final g = Game(
    content: content,
    store: store ?? MemoryKeyValue(),
    ai: AiClient(
      const AiConfig(endpoint: 'http://model/v1', model: 'test'),
      client: m.client,
    ),
    surprises: false,
    unlockAll: true,
    now: now,
  );
  await g.load();
  return (g, m);
}

String system(Map<String, dynamic> call) => '${(call['messages'] as List)[0]['content']}';

void main() {
  group('🧠 she remembers you', () {
    test('your last visit, even before you are friends: walked away yesterday', () async {
      var day = DateTime(2026, 12, 2, 10);
      final store = MemoryKeyValue();
      var (g, m) = await aiGame(() => day, store: store);
      final r = await g.start('lim', 'pomfret', 'none');
      await g.move(r['id'] as String, move: 'walk');
      day = DateTime(2026, 12, 3, 10);
      (g, m) = await aiGame(() => day, store: store);
      await g.start('lim', 'pomfret', 'none');
      final greet = system(m.says.last);
      expect(greet, contains('walked away'));
      expect(greet, contains('yesterday'));
    });

    test('rudeness is remembered', () async {
      var day = DateTime(2026, 12, 2, 10);
      final store = MemoryKeyValue();
      var (g, m) = await aiGame(
        () => day,
        store: store,
        model: FakeModel(move: '{"move": "rude", "price": null}'),
      );
      final r = await g.start('lim', 'pomfret', 'none');
      final id = r['id'] as String;
      for (var i = 0; i < 6; i++) {
        final x = await g.move(id, text: 'you stupid');
        if (x['done'] == true) break;
      }
      day = DateTime(2026, 12, 3, 10);
      (g, m) = await aiGame(() => day, store: store);
      await g.start('lim', 'pomfret', 'none');
      expect(system(m.says.last), contains('was rude to you yesterday'));
    });

    test('gossip: a hard bargain at another stall, never a number', () async {
      final day = DateTime(2026, 12, 3, 10);
      final store = MemoryKeyValue();
      await store.write(
        'profile',
        jsonEncode({
          'name': 'Tester',
          'haggles': [
            {'stall': 'lim', 'item': 'pomfret', 'result': 'deal', 'deal': 13, 'stars': 3, 'day': '2026-12-02'},
          ],
        }),
      );
      final (g, _) = await aiGame(() => day, store: store);
      final notes = [for (var seed = 0; seed < 40; seed++) g.memoryGreet('mei', seed)];
      final gossip = notes.where((n) => n.contains('Uncle Lim told you')).toList();
      expect(gossip.length, inInclusiveRange(10, 30), reason: 'about one greeting in two');
      expect(gossip.first, contains('yesterday'));
      for (final n in notes) {
        expect(RegExp(r'\d').hasMatch(n), isFalse, reason: n);
      }
      expect(g.memoryGreet('lim', 0), contains('bargained you down very hard yesterday'));
      // older news is not gossip
      final (late, _) = await aiGame(() => DateTime(2026, 12, 9, 10), store: store);
      expect([for (var s = 0; s < 10; s++) late.memoryGreet('mei', s)].every((n) => !n.contains('told you')), isTrue);
    });

    test('item names lose their numbers in notes', () {
      expect(plainName('tray of kampung eggs (10)'), 'tray of kampung eggs');
      expect(plainName('durian (1 kg)'), 'durian');
      expect(plainName('box of mangoes'), 'box of mangoes');
    });
  });

  group('🙄 poking her again', () {
    test('a second flirt gets comic exasperation; the first does not', () async {
      final (g, m) = await aiGame(
        () => DateTime(2026, 12, 2, 10),
        model: FakeModel(move: '{"move": "flirt", "price": null}'),
      );
      final r = await g.start('mei', 'mango', 'none');
      final id = r['id'] as String;
      await g.move(id, text: 'auntie you so pretty, date me');
      expect(system(m.says.last), isNot(contains('keep flirting')));
      await g.move(id, text: 'come on, one date');
      expect(system(m.says.last), contains('keep flirting'));
    });

    test('rude again: fed up', () async {
      final (g, m) = await aiGame(
        () => DateTime(2026, 12, 2, 10),
        model: FakeModel(move: '{"move": "rude", "price": null}'),
      );
      final r = await g.start('raj', 'case', 'none');
      final id = r['id'] as String;
      await g.move(id, text: 'you cheat');
      expect(system(m.says.last), isNot(contains('AGAIN')));
      final x = await g.move(id, text: 'cheater lah');
      if (x['done'] != true) expect(system(m.says.last), contains('AGAIN'));
    });
  });

  group('🥭 a sure first win', () {
    test('following Mum (a low offer, then a bit higher) gets two stars in a few moves, with no surprise', () async {
      for (var seed = 0; seed < 25; seed++) {
        final g = Game(content: content, store: MemoryKeyValue(), random: math.Random(seed));
        await g.load();
        var r = await g.start('mei', 'mango');
        expect(r['surprise'], '', reason: 'no market surprise in the very first haggle');
        final id = r['id'] as String;
        var moves = 0;
        while (r['done'] != true && moves < 8) {
          if (r['pending'] != null) {
            r = await g.move(id, move: 'confirm');
            break;
          }
          final sug = (r['suggestions'] as List).cast<Map>();
          final offers = [
            for (var i = 0; i < sug.length; i++)
              if (sug[i]['move'] == 'offer') i,
          ];
          r = await g.move(id, pick: moves == 0 ? offers.first : offers.last);
          moves++;
        }
        expect(r['result'], 'deal', reason: 'seed $seed');
        expect(r['stars'], greaterThanOrEqualTo(2), reason: 'seed $seed');
        expect(moves, lessThanOrEqualTo(4), reason: 'seed $seed');
        expect('${r['notes']}', contains("Come back tomorrow: Uncle Wong's stall opens!"));
      }
    });

    test('a new stall gets 🆕 and a word from Mum until you visit it', () async {
      var day = DateTime(2026, 12, 2, 10);
      final g = Game(content: content, store: MemoryKeyValue(), random: math.Random(1), now: () => day);
      await g.load();
      Map stall(String id) => (g.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == id);
      // walks away (a second time if she calls them back)
      Future<Map> leave(Map r) async {
        var x = await g.move(r['id'] as String, move: 'walk');
        if (x['done'] != true) x = await g.move(r['id'] as String, move: 'walk');
        return x;
      }

      var r = await g.start('mei', 'mango');
      await leave(r);
      expect(stall('mei')['new'], isFalse, reason: 'the first stalls are never new');
      expect(stall('wong')['locked'], isTrue);
      expect(g.today()['try'], isNull);
      day = DateTime(2026, 12, 3, 10);
      r = await g.start('lim', 'pomfret');
      await leave(r);
      expect(stall('wong')['locked'], isFalse);
      expect(stall('wong')['new'], isTrue);
      expect((g.today()['try'] as Map)['stall'], 'wong');
      r = await g.start('wong', 'tiffin');
      await leave(r);
      expect(stall('wong')['new'], isFalse);
      expect(g.today()['try'], isNull);
      // no "come back tomorrow" after the first haggle
      final x = await leave(await g.start('mei', 'mango'));
      expect('${x['notes']}', isNot(contains('Come back tomorrow')));
    });
  });

  group('🧱 a best price given too early', () {
    Future<(Game, Map)> firmEarly() async {
      final g = Game(
        content: content,
        store: MemoryKeyValue(),
        random: math.Random(3),
        surprises: false,
        unlockAll: true,
      );
      await g.load();
      // (finish one haggle first: the very first one is the gentle one)
      final w = await g.start('mei', 'mango', 'none');
      var x = await g.move(w['id'] as String, move: 'walk');
      if (x['done'] != true) await g.move(w['id'] as String, move: 'walk');
      final r = await g.start('raj', 'powerbank', 'none');
      await g.move(r['id'] as String, text: '30 can?');
      x = await g.move(r['id'] as String, text: 'I only have \$20'); // a stated limit, too early
      return (g, x);
    }

    test('saying the same number twice is pressure, not a promise: nothing gets locked', () async {
      final g = Game(
        content: content,
        store: MemoryKeyValue(),
        random: math.Random(3),
        surprises: false,
        unlockAll: true,
      );
      await g.load();
      final w = await g.start('mei', 'mango', 'none');
      if ((await g.move(w['id'] as String, move: 'walk'))['done'] != true) {
        await g.move(w['id'] as String, move: 'walk');
      }
      final r = await g.start('raj', 'powerbank', 'none');
      final id = r['id'] as String;
      final a = await g.move(id, text: '20 can?');
      final b = await g.move(id, text: '20 can?');
      expect(b['event'], 'same_offer');
      expect(b['ask'], a['ask'], reason: 'she holds');
      expect(b.containsKey('firm_note'), isFalse);
      final c = await g.move(id, text: '24 can?');
      expect(c['event'], isNot('final'), reason: 'coming up still bargains');
      expect(c['ask'] as num, lessThan(b['ask'] as num));
    });

    test('a stated limit too early: a best price, and the game says why', () async {
      final (_, x) = await firmEarly();
      expect(x['event'], 'budget_best');
      expect('${x['firm_note']}', contains('You gave \$20 as your limit'));
      expect(x['ask'] as num, greaterThan(20 * 1.06)); // above her real lowest: it was too early
    });

    test('her soft spot reopens it once: she comes down, never below her real lowest', () async {
      final (g, x) = await firmEarly();
      final id = x['id'] as String;
      final best = x['ask'] as num;
      var y = await g.move(id, text: '21 can?');
      expect(y['ask'], best, reason: 'still her best price');
      expect(y.containsKey('firm_note'), isFalse, reason: 'the note shows once');
      y = await g.move(id, text: 'boss you watch the cricket last night?');
      expect(y['ask'] as num, lessThan(best));
      expect(y['ask'] as num, greaterThanOrEqualTo(18)); // her real lowest is about $20 (never below 90% of it)
      // bargaining works again
      var last = y['ask'] as num;
      for (final o in [21, 22, 22.5]) {
        if (y['done'] == true || y['pending'] != null) break;
        y = await g.move(id, text: '\$$o can?');
        expect(y['ask'] as num, lessThanOrEqualTo(last));
        last = y['ask'] as num;
      }
    });
  });

  group('🔢 numbers people actually type', () {
    Future<(Game, String, num)> mango() async {
      final g = Game(
        content: content,
        store: MemoryKeyValue(),
        random: math.Random(4),
        surprises: false,
        unlockAll: true,
      );
      await g.load();
      final r = await g.start('mei', 'mango', 'none');
      return (g, r['id'] as String, r['ask'] as num);
    }

    for (final (text, want) in const [
      ('10% off can?', 16.0), // 18 less 10%: 16.20, said as $16
      ('discount 20% lah', 14.5),
      ('half price can?', 9.0),
      ('\$5 discount can?', 13.0),
      ('cheaper by 3 can?', 15.0),
      ('fifteen dollars ok?', 15.0),
      ('I come here 10 years, 14 can?', 14.0),
    ]) {
      test('"$text" is an offer of \$$want', () async {
        final (g, id, _) = await mango();
        final r = await g.move(id, text: text);
        expect(['counter', 'confirm', 'final', 'insulted'], contains(r['event']), reason: text);
        expect(r['offer'], want, reason: text);
      });
    }

    test('100% off is a question, not an offer of nothing', () async {
      final (g, id, ask) = await mango();
      final r = await g.move(id, text: '100% off can?');
      expect(r['event'], 'clarify');
      expect(r['ask'], ask);
    });
  });

  group('🧠 her private thinking never shows', () {
    test('a reply with leaked thinking: only the answer after it is used', () async {
      final m = FakeModel(line: 'Eh bro, welcome back! \$38.</think>Eh bro, back again sia! Today \$38 only!');
      final ai = AiClient(
        const AiConfig(endpoint: 'http://model/v1', model: 'test'),
        client: m.client,
      );
      expect(await ai.chat('You are Ah Boy', 'hi'), 'Eh bro, back again sia! Today \$38 only!');
      m.line = '<think>She should greet warmly.</think>Morning my dear!';
      expect(await ai.chat('You are Auntie Mei', 'hi'), 'Morning my dear!');
      m.line = '<think>still thinking and never stopped';
      expect(await ai.chat('You are Auntie Mei', 'hi'), '');
    });

    test('in a haggle: the stallholder never says a tag', () async {
      final (g, m) = await aiGame(
        () => DateTime(2026, 12, 2, 10),
        model: FakeModel(line: 'Draft line.</think>Aiyo, too low lah my dear!'),
      );
      final r = await g.start('mei', 'mango', 'none');
      final x = await g.move(r['id'] as String, text: 'how is business today?');
      expect('${x['line']}', isNot(contains('<')));
      expect('${x['line']}', isNot(contains('think')));
      if (x['ai_line'] == true) expect(x['line'], 'Aiyo, too low lah my dear!');
    });
  });

  test('😠 the first insult in a haggle says so (once); a fair offer after it still moves her', () async {
    final g = Game(
      content: content,
      store: MemoryKeyValue(),
      random: math.Random(3),
      surprises: false,
      unlockAll: true,
    );
    await g.load();
    final w = await g.start('mei', 'mango', 'none');
    if ((await g.move(w['id'] as String, move: 'walk'))['done'] != true) {
      await g.move(w['id'] as String, move: 'walk');
    }
    final r = await g.start('rosnah', 'tray', 'none');
    final id = r['id'] as String;
    var x = await g.move(id, text: '20 can?');
    expect(x['event'], 'insulted');
    expect('${x['firm_note']}', contains('offended'));
    x = await g.move(id, text: '25 can?');
    expect(x['event'], 'insulted');
    expect(x.containsKey('firm_note'), isFalse, reason: 'once a haggle');
    for (final low in [30, 35]) {
      x = await g.move(id, text: '$low can?');
    }
    x = await g.move(id, text: '45 can?');
    expect(x['event'], 'counter');
    expect(x['ask'] as num, lessThan(80));
  });

  group('📦 the pieces in one pack are not a quantity', () {
    Future<(Game, String)> at(String stall, String item, {FakeModel? model}) async {
      final g = model == null
          ? Game(content: content, store: MemoryKeyValue(), random: math.Random(3), surprises: false, unlockAll: true)
          : (await aiGame(() => DateTime(2026, 12, 2, 10), model: model)).$1;
      await g.load();
      final w = await g.start('boy', 'yoyo', 'none'); // (the first haggle is the gentle one: get it out of the way)
      await g.move(w['id'] as String, move: 'buy');
      final r = await g.start(stall, item, 'none');
      return (g, r['id'] as String);
    }

    for (final (text, want) in const [
      ('30 for 20 nasi lemak', 30.0),
      ('can do 45 for 20 packets?', 45.0),
      ('20 packets 50 can?', 50.0),
    ]) {
      test('"$text": one tray, for \$$want', () async {
        final (g, id) = await at('rosnah', 'tray');
        final r = await g.move(id, text: text);
        expect(r['qty'], 1);
        expect(r['offer'], want);
      });
    }

    test('the AI read 20 as a quantity: still one tray, and she never offers you two', () async {
      final m = FakeModel(
        move: '{"move": "bulk", "price": 30, "per": "total", "qty": 20}',
        line: 'Aiyoh sayang, too low lah!',
      );
      final (g, id) = await at('rosnah', 'tray', model: m);
      final r = await g.move(id, text: 'auntie 30 for 20 nasi lemak can?');
      expect(r['qty'], 1);
      expect(r['offer'], 30);
      expect('${m.says.last['messages']}', isNot(contains('only have two left')));
    });

    test('a plain "20 can?" is still a price; a budget stays a budget; 10% off stays a percentage', () async {
      var (g, id) = await at('rosnah', 'tray');
      expect((await g.move(id, text: '20 can?'))['offer'], 20);
      (g, id) = await at('rosnah', 'tray');
      final b = await g.move(id, text: 'I only have 60 for 20 packets');
      expect(b['offer'], 60);
      expect(['confirm', 'budget_best'], contains(b['event']), reason: 'a stated limit');
      (g, id) = await at('rosnah', 'tray');
      expect((await g.move(id, text: '10% off for 20 packets?'))['offer'], 72);
    });

    test('a box of 6 mangoes: "6 mangoes for 15" is one box; two trays is still two', () async {
      final (g, id) = await at('mei', 'mango');
      final r = await g.move(id, text: '6 mangoes for 15 can?');
      expect(r['qty'], 1);
      expect(r['offer'], 15);
      final (g2, id2) = await at('rosnah', 'tray');
      final two = await g2.move(id2, text: 'I take two trays, cheaper?');
      expect(two['qty'], 2);
    });
  });
}
