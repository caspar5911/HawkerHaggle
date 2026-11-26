// How fair is the game? Plays thousands of haggles (no AI: the word rules and the engine only) with different kinds of
// players at every stall, and prints how often each gets a deal, their stars and their discount.
// Run: dart run tool/balance.dart [haggles per item per player, default 40]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:hawker_haggle/core/game.dart';

typedef Player = Future<Map> Function(Game g, Map r, math.Random rnd);

Future<Map> finish(Game g, String id, Map r) async {
  if (r['pending'] != null && r['done'] != true) r = await g.move(id, move: 'confirm');
  return r;
}

/// Taps the suggestion at [which] (0 bold, 1 safer, 2 trick) until she's firm or tired, then takes her price.
Player tapper(int Function(math.Random) which) => (g, r, rnd) async {
  final id = r['id'] as String;
  for (var i = 0; i < 30 && r['done'] != true; i++) {
    if (r['pending'] != null) return finish(g, id, r);
    if (const ['final', 'budget_best', 'callback'].contains(r['event']) || (r['patience'] as num) < 35) {
      r = await g.move(id, move: 'accept');
      continue;
    }
    final sug = (r['suggestions'] as List).cast<Map>();
    final n = sug.length;
    // 1: the safer offer (the last offer shown), 0: the bold one (the first), 2: anything
    final w = which(rnd);
    final pick = w == 1 ? sug.lastIndexWhere((s) => s['move'] == 'offer') : (w == 0 ? 0 : rnd.nextInt(math.max(1, n)));
    r = await g.move(id, pick: n == 0 ? null : pick, text: n == 0 ? 'can cheaper?' : null);
  }
  return finish(g, id, r);
};

/// A sensible typer: a compliment, then 65% of her price, coming up 6% at a time; walks away once at her last price.
Future<Map> smart(Game g, Map r, math.Random rnd) async {
  final id = r['id'] as String;
  final open = (r['ask'] as num).toDouble();
  r = await g.move(id, text: 'wah your stall so nice, everything looks good!');
  var offer = open * 0.65;
  var walked = false;
  for (var i = 0; i < 20 && r['done'] != true; i++) {
    if (r['pending'] != null) return finish(g, id, r);
    final ask = (r['ask'] as num).toDouble();
    if (const ['final', 'budget_best'].contains(r['event']) && !walked) {
      walked = true;
      r = await g.move(id, move: 'walk');
      continue;
    }
    if (const ['final', 'budget_best', 'callback'].contains(r['event']) || (r['patience'] as num) < 30) {
      r = await g.move(id, move: 'accept');
      continue;
    }
    if (offer >= ask) {
      r = await g.move(id, move: 'accept');
      continue;
    }
    r = await g.move(id, text: '\$${offer.toStringAsFixed(0)} can?');
    offer += open * 0.06;
  }
  return finish(g, id, r);
}

/// Pays the first price.
Future<Map> payer(Game g, Map r, math.Random rnd) async {
  final id = r['id'] as String;
  return finish(g, id, await g.move(id, move: 'accept'));
}

/// Keeps offering 40% and never comes up.
Future<Map> lowballer(Game g, Map r, math.Random rnd) async {
  final id = r['id'] as String;
  final low = ((r['ask'] as num) * 0.4).round();
  for (var i = 0; i < 20 && r['done'] != true; i++) {
    if (r['pending'] != null) return finish(g, id, r);
    r = await g.move(id, text: '\$$low can?');
  }
  return finish(g, id, r);
}

Future<void> main(List<String> args) async {
  final per = args.isEmpty ? 40 : int.parse(args.first);
  final helpers = args.contains('helpers'); // own the haggling helpers from the shop
  final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;
  final players = <String, Player>{
    'pays full price': payer,
    'taps the safer offer': tapper((_) => 1),
    'taps the bold offer': tapper((_) => 0),
    'taps anything': tapper((_) => 2),
    'types sensibly': smart,
    'lowballs': lowballer,
  };
  final rnd = math.Random(7);
  stdout.writeln('| player | deal | ⭐ avg | ⭐⭐⭐ | refused | lost to rival | avg off |');
  stdout.writeln('|---|---|---|---|---|---|---|');
  final byStall = <String, List<num>>{}; // taps the safer offer: [deals, n, stars]
  for (final MapEntry(key: name, value: play) in players.entries) {
    var n = 0, deals = 0, stars = 0, three = 0, refused = 0, lost = 0;
    var off = 0.0;
    for (final st in (content['stalls'] as List).cast<Map>()) {
      for (final it in (st['items'] as List).cast<Map>()) {
        for (var k = 0; k < per; k++) {
          final g = Game(
            content: content,
            store: MemoryKeyValue(),
            random: math.Random(rnd.nextInt(1 << 30)),
            unlockAll: true,
            surprises: true,
            walletOn: false, // (how fair the haggling is: money doesn't come into it)
          );
          await g.load();
          if (helpers) {
            // 🍀 the lucky charm and 🌸 the flowers from the shop: more patience and a better mood from the start
            g.progress.addToJar(140);
            await g.buyGoal('charm');
            await g.buyGoal('flowers');
          }
          final r0 = await g.start('${st['id']}', '${it['id']}');
          final r = await play(g, r0, rnd);
          n++;
          final s = ((r['stars'] ?? 0) as num).toInt();
          if (r['result'] == 'deal') {
            deals++;
            stars += s;
            if (s == 3) three++;
            off += 1 - (r['deal'] as num) / (r0['ask'] as num);
          }
          if (r['result'] == 'refused') refused++;
          if (r['result'] == 'lost') lost++;
          if (name == 'taps the safer offer') {
            final b = byStall.putIfAbsent('${st['name']}', () => [0, 0, 0]);
            b[1] += 1;
            if (r['result'] == 'deal') {
              b[0] += 1;
              b[2] += s;
            }
          }
        }
      }
    }
    String pc(num x) => '${(100 * x / n).round()}%';
    stdout.writeln(
      '| $name | ${pc(deals)} | ${deals == 0 ? '-' : (stars / deals).toStringAsFixed(1)} | ${pc(three)} | '
      '${pc(refused)} | ${pc(lost)} | ${deals == 0 ? '-' : '${(100 * off / deals).round()}%'} |',
    );
  }
  stdout.writeln('\nTaps the safer offer, by stall (deal rate, average stars):');
  for (final MapEntry(key: s, value: b) in byStall.entries) {
    stdout.writeln(
      '  $s: ${(100 * b[0] / b[1]).round()}% deals, ${b[0] == 0 ? '-' : (b[2] / b[0]).toStringAsFixed(1)} ⭐',
    );
  }
}
