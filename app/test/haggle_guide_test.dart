// The tip for next time and the 📖 Haggling guide.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/haggle_guide.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

Future<Game> newGame() async {
  final g = Game(
    content: content,
    store: MemoryKeyValue(),
    random: math.Random(4),
    unlockAll: true,
    surprises: false,
    now: () => DateTime(2026, 12, 2, 10), // an ordinary day
  );
  await g.load();
  return g;
}

String tip({
  String result = 'deal',
  int rounds = 5,
  int stars = 1,
  Set<String> tactics = const {},
  Set<String> events = const {},
  bool walkedAway = false,
  bool calledBack = false,
  double? firstOffer = 0.7,
  bool kindWordNoted = false,
}) => coachTip(
  result: result,
  rounds: rounds,
  stars: stars,
  tactics: tactics,
  events: events,
  walkedAway: walkedAway,
  calledBack: calledBack,
  who: 'Auntie Mei',
  firstOffer: firstOffer,
  kindWordNoted: kindWordNoted,
);

void main() {
  test('the tip for next time fits what happened, the most useful one first', () {
    expect(tip(result: 'lost'), contains('Auntie Rose'));
    expect(tip(events: {'insulted', 'final'}), contains('cross'));
    expect(tip(result: 'refused'), contains('ran out of patience'));
    expect(tip(result: 'walked'), contains('Walking away works best'));
    expect(tip(result: 'walked', calledBack: true, stars: 0, rounds: 4), isNot(contains('Walking away works best')));
    expect(tip(rounds: 1), contains('paid her first price'));
    expect(tip(firstOffer: 0.92), contains('first offer was close'));
    expect(tip(events: {'final'}), contains('try walking away'));
    expect(tip(events: {'final'}, walkedAway: true), contains('Be nice first'));
    expect(tip(tactics: {'compliment'}), contains('next door'));
    expect(tip(kindWordNoted: true), contains('next door')); // not said twice
    expect(tip(stars: 3, tactics: {'compliment', 'competitor'}), contains('perfect'));
    expect(tip(stars: 2, tactics: {'compliment', 'competitor'}), contains('Haggling guide'));
  });

  test('a trick is learned by using it; hidden ones only show a hint', () {
    expect(learnedTricks([]), isEmpty);
    final learned = learnedTricks([
      {
        'result': 'deal',
        'saved': 0.2,
        'tactics': ['compliment', 'pity'],
        'qty': 2,
      },
      {'result': 'refused', 'tactics': <String>[], 'heard_final': true},
      {
        'result': 'deal',
        'saved': 0.05,
        'called_back': true,
        'combos': 1,
        'tactics': ['budget'],
      },
    ], softSpots: 1);
    expect(learned, {
      'open', 'compliment', 'plead', 'bulk', 'patience', 'final', 'walk', 'tagteam', 'budget', 'softspot', //
    });
    expect(tricks.map((t) => t.$1).toSet().length, tricks.length); // ids are unique
  });

  test('a real haggle: paying the first price gets the tip, and the guide and me() count tricks', () async {
    final g = await newGame();
    var r = await g.start('mei', 'mango', 'none');
    r = await g.move(r['id'] as String, move: 'buy');
    expect(r['result'], 'deal');
    expect(r['coach'], contains('paid her first price'));
    expect(g.me()['tricks'], 0);
    // a compliment, an offer, then buy: the compliment trick is learned
    r = await g.start('mei', 'durian', 'none');
    final id = r['id'] as String;
    await g.move(id, text: 'wah auntie your durian smells so good!');
    await g.move(id, text: '\$22 can?');
    for (var i = 0; i < 6 && r['done'] != true; i++) {
      r = await g.move(id, move: r['pending'] != null ? 'confirm' : 'buy');
    }
    expect(r['coach'], isA<String>());
    final guide = g.guide();
    final byId = {for (final t in (guide['tricks'] as List).cast<Map>()) t['id']: t};
    expect(byId['compliment']!['learned'], isTrue);
    expect(byId['compliment']!['title'], 'Say something nice');
    expect(byId['walk']!['learned'], isFalse);
    expect(byId['walk']!.containsKey('title'), isFalse); // hidden: only a hint
    expect(byId['walk']!['hint'], isNotEmpty);
    expect(guide['total'], tricks.length);
    expect(g.me()['tricks'], guide['learned']);
    expect((guide['real_life'] as List).join(' '), contains('chicken rice'));
  });

  test('an insulting offer: the tip says so; a mid-haggle answer has no tip', () async {
    final g = await newGame();
    var r = await g.start('lim', 'pomfret', 'none');
    final id = r['id'] as String;
    r = await g.move(id, text: '\$3');
    expect(r['coach'], isNull); // not over yet
    for (var i = 0; i < 12 && r['done'] != true; i++) {
      r = await g.move(id, move: 'walk');
    }
    expect(r['done'], isTrue);
    expect(r['coach'], contains('cross'));
  });
}
