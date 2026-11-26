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
}
