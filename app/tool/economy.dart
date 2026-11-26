// The wallet's economy, played out: a casual player for three weeks (Mum's list, a couple of things to sell, selling
// them at their own stall, saving some), with and without the wallet. Are they ever stuck? Can they afford a
// legendary item? When do the jar goals come? No AI: the engine and the word rules only.
// Run: dart run tool/economy.dart [players, default 20]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/legendary.dart';
import 'package:hawker_haggle/core/progress.dart' show dayKey;

/// Haggles like a sensible tapper: the bold offer first, then the safer one; takes her last price.
Future<Map> haggle(Game g, String stall, String item) async {
  var r = await g.start(stall, item);
  final id = r['id'] as String;
  for (var i = 0; i < 30 && r['done'] != true; i++) {
    try {
      if (r['pending'] != null) {
        r = await g.move(id, move: 'confirm');
      } else if (const ['final', 'budget_best', 'callback'].contains(r['event']) || (r['patience'] as num) < 35) {
        r = await g.move(id, move: 'accept');
      } else {
        final sug = (r['suggestions'] as List).cast<Map>();
        final offers = [
          for (var k = 0; k < sug.length; k++)
            if (sug[k]['move'] == 'offer') k,
        ];
        r = await g.move(id, pick: i == 0 ? offers.first : offers.last);
      }
    } on GameError {
      return {'result': 'short'}; // can't pay (or no room): walks off
    }
  }
  return r;
}

Future<void> main(List<String> args) async {
  final players = args.isEmpty ? 20 : int.parse(args.first);
  final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;
  for (final (wallet, chase) in const [(false, true), (true, true), (true, false)]) {
    final cake = <int>[], awning = <int>[], scooter = <int>[];
    var shortDays = 0, legendDays = 0, legendBought = 0, minWallet = 1e9, maxWallet = 0.0;
    final why = <String, int>{};
    final shortBy = <String>[];
    for (var pl = 0; pl < players; pl++) {
      var day = DateTime(2026, 12, 1, 10);
      final rnd = math.Random(pl);
      final g = Game(
        content: content,
        store: MemoryKeyValue(),
        random: math.Random(pl + 100),
        unlockAll: true,
        walletOn: wallet,
        now: () => day,
      );
      await g.load();
      int? gotCake, gotAwning, gotScooter;
      for (var d = 1; d <= 21; d++) {
        g.me(); // opens the game: Mum's pocket money
        var short = false;
        // Mum's list
        for (final i in (g.today()['items'] as List).cast<Map>()) {
          await haggle(g, '${i['stall']}', '${i['item']}');
        }
        // a legendary day: try for it
        final legend = legendaryOn(dayKey(day));
        if (legend != null && chase) {
          legendDays++;
          final before = g.progress.wallet;
          final r = await haggle(g, legend.stall, '${legend.item['id']}');
          if (r['result'] == 'deal') legendBought++;
          why['${r['result']}'] = (why['${r['result']}'] ?? 0) + 1;
          if (r['result'] == 'short') {
            shortBy.add('had \$${before.toStringAsFixed(0)}, ${legend.item['id']} floor \$${legend.item['floor']}');
          }
          if (r['result'] == 'short') short = true;
        }
        // two things to sell: something they can afford (with the wallet, about 80% of the first price)
        for (var k = 0; k < 2; k++) {
          final choices = [
            for (final st in (content['stalls'] as List).cast<Map>().take(4))
              for (final it in (st['items'] as List).cast<Map>())
                if (!wallet || (it['ask'] as num) * 0.8 <= g.progress.wallet) (st, it),
          ];
          if (choices.isEmpty) break;
          final (st, it) = choices[rnd.nextInt(choices.length)];
          final r = await haggle(g, '${st['id']}', '${it['id']}');
          if (r['result'] == 'short') short = true;
        }
        // sell at your own stall: ask the usual price, else take their offer
        for (var k = 0; k < 3 && g.progress.stock.isNotEmpty; k++) {
          var s = await g.shopStart();
          final fair = (s['product'] as Map)['fair'] as num;
          s = await g.shopMove(s['id'] as String, ask: fair.toDouble());
          if (s['done'] != true) s = await g.shopMove(s['id'] as String, take: true);
        }
        if (short) shortDays++;
        // saving: with a wallet, a few dollars when there's more than Mum's pocket money
        // a legendary item announced for the next few days: keep the money in the wallet for it
        final soon = chase && nextLegendary(day, within: 3) != null;
        final spare = ((g.progress.wallet - (soon ? 100 : 30)) / 3).floorToDouble();
        if (wallet && spare >= 1) await g.saveToJar(spare);
        if (wallet) {
          minWallet = math.min(minWallet, g.progress.wallet);
          maxWallet = math.max(maxWallet, g.progress.wallet);
        }
        // goals, in order, as soon as the jar allows
        for (final (id, cost) in const [('cake', 30.0), ('awning', 80.0), ('scooter', 150.0)]) {
          if (!g.progress.owns(id) && g.progress.jar >= cost) {
            await g.buyGoal(id);
            if (id == 'cake') gotCake = d;
            if (id == 'awning') gotAwning = d;
            if (id == 'scooter') gotScooter = d;
          }
        }
        day = day.add(const Duration(days: 1));
      }
      if (gotCake != null) cake.add(gotCake);
      if (gotAwning != null) awning.add(gotAwning);
      if (gotScooter != null) scooter.add(gotScooter);
    }
    String when(List<int> days) => days.isEmpty
        ? 'never'
        : 'day ${(days.reduce((a, b) => a + b) / days.length).toStringAsFixed(1)} on average '
              '(${days.length}/$players players)';
    stdout.writeln(
      wallet
          ? '\n👛 WITH THE WALLET, ${chase ? 'buying every legendary item' : 'saving for the jar goals instead'}'
          : '🫙 WITHOUT (as now)',
    );
    stdout.writeln('  cake (\$30): ${when(cake)}');
    stdout.writeln('  awning (\$80): ${when(awning)}');
    stdout.writeln('  scooter (\$150): ${when(scooter)}');
    stdout.writeln('  legendary: bought $legendBought of $legendDays tries');
    stdout.writeln('  legendary results: $why');
    stdout.writeln('  short examples: ${shortBy.take(6).join('; ')}');
    stdout.writeln('  days a purchase was out of reach: $shortDays of ${21 * players}');
    if (wallet) {
      stdout.writeln('  wallet: lowest \$${minWallet.toStringAsFixed(2)}, highest \$${maxWallet.toStringAsFixed(2)}');
    }
  }
}
