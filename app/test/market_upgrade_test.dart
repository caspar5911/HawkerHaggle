import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map;

Future<Game> game(MemoryKeyValue store) async {
  final game = Game(content: content, store: store, now: () => DateTime(2026, 11, 24), surprises: false);
  await game.load();
  return game;
}

Future<Map<String, Object?>> move(Game g, Map view, String text) => g.move(view['id'] as String, text: text);

void main() {
  test('Mei welcomes the first compliment and calls out repeated flattery', () async {
    final g = await game(MemoryKeyValue());
    final start = await g.start('mei', 'mango');
    final first = await move(g, start, 'wah your fruit looks so good');
    final second = await move(g, first, 'wah your fruit looks so good');
    expect(first['event'], 'flattered');
    expect(first['mood'] as num, greaterThan(start['mood'] as num));
    expect(second['event'], 'flattery_tired');
    expect(second['ask'], first['ask']);
  });

  test('Lim makes a better counter when you open with a credible offer', () async {
    final g = await game(MemoryKeyValue());
    final direct = await g.start('lim', 'prawns');
    final directCounter = await move(g, direct, r'$17 can?');
    final chat = await g.start('lim', 'prawns');
    await move(g, chat, 'hello');
    await move(g, chat, 'hello again');
    final laterCounter = await move(g, chat, r'$17 can?');
    expect(directCounter['event'], 'counter');
    expect(directCounter['ask'] as num, lessThan(laterCounter['ask'] as num));
    expect((directCounter['tells'] as List).join(), contains('straight offer'));
  });

  test('Raj suggests a bundle and dropping back to one removes the bundle discount', () async {
    final g = await game(MemoryKeyValue());
    final start = await g.start('raj', 'case');
    final suggestions = (start['suggestions'] as List).cast<Map>();
    final bulk = suggestions.indexWhere((s) => s['move'] == 'bulk');
    expect(bulk, greaterThanOrEqualTo(0));
    final bundle = await g.move(start['id'] as String, pick: bulk);
    expect(bundle['qty'], 2);
    expect(bundle['ask'] as num, lessThan(start['ask'] as num));
    expect((bundle['tells'] as List).join(), contains('for both'));
    final one = await g.move(start['id'] as String, move: 'one');
    expect(one['qty'], 1);
    expect(one['ask'], start['ask']);
  });

  test('the wedding changes with completed chapters and the chosen role survives a reload', () async {
    final store = MemoryKeyValue();
    await store.write(
      'profile',
      jsonEncode({
        'name': 'Shiok Otter',
        'friends': {
          'mei': {'points': 100, 'visits': 3},
        },
      }),
    );
    final g = await game(store);
    Map? wedding(Game g) => g.stalls()['wedding'] as Map?;
    expect(wedding(g), isNull);
    expect(await g.chooseWedding('stall'), isFalse);

    Future<void> buy(String stall, String item) async {
      final start = await g.start(stall, item);
      await g.move(start['id'] as String, move: 'buy');
    }

    await buy('mei', 'mango');
    expect(wedding(g)?['stage'], 1);
    await buy('lim', 'prawns');
    expect(wedding(g)?['stage'], 1);

    final prawns = await g.start('lim', 'prawns');
    var next = prawns;
    for (final text in [r'$16 can?', r'$17 can?', r'$18 can?', r'$19 can?', r'$20 can?']) {
      next = await move(g, next, text);
      if (next['pending'] != null) break;
    }
    expect(next['pending'], isNotNull);
    final deal = await g.move(next['id'] as String, move: 'confirm');
    expect(deal['stars'] as num, greaterThanOrEqualTo(2));
    expect(wedding(g)?['stage'], 2);
    expect(await g.chooseWedding('unknown'), isFalse);
    expect(await g.chooseWedding('stall'), isTrue);
    expect(await g.chooseWedding('table'), isFalse);

    await buy('mei', 'mango');
    final saved = wedding(g);
    expect(saved?['stage'], 3);
    expect(saved?['choice'], 'stall');

    final reloaded = await game(store);
    expect(wedding(reloaded), saved);
    final mei = (reloaded.stalls()['stalls'] as List).cast<Map>().firstWhere((s) => s['id'] == 'mei');
    expect(mei['wedding'], saved);
    final lim = await reloaded.start('lim', 'prawns');
    expect(lim['line'], contains('wedding'));
  });

  test('an older completed story gets a wedding photo without another reward', () async {
    final store = MemoryKeyValue();
    await store.write(
      'profile',
      jsonEncode({
        'name': 'Shiok Otter',
        'arcs': {
          'mei': {'done': 3},
        },
      }),
    );
    final g = await game(store);
    final before = g.progress.jar;
    expect((g.stalls()['wedding'] as Map)['stage'], 3);
    expect(await g.chooseWedding('table'), isFalse);
    expect(g.progress.jar, before);
  });
}
