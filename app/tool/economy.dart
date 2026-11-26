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
import 'package:hawker_haggle/core/treats.dart' show goals;

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
  final days = args.length > 1 ? int.parse(args[1]) : 45;
  final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;
  // (wallet on?, buys every legendary?, trades the priciest things it can afford, as much as it can?)
  for (final (wallet, chase, trader) in const [
    (false, true, false),
    (true, true, false),
    (true, false, false),
    (true, false, true),
  ]) {
    final got = <String, List<int>>{}; // shop item -> the day each player bought it
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
      for (var d = 1; d <= days; d++) {
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
        // things to sell: something they can afford (with the wallet, about 80% of the first price); the trader buys
        // the priciest they can, from every stall, until the stock is full
        for (var k = 0; k < (trader ? 10 : 2); k++) {
          final choices = [
            for (final st in (content['stalls'] as List).cast<Map>().take(trader ? 11 : 4))
              for (final it in (st['items'] as List).cast<Map>())
                if ((!wallet || (it['ask'] as num) * 0.8 <= g.progress.wallet) &&
                    g.progress.goesToStock('${st['id']}', '${it['id']}'))
                  (st, it),
          ];
          if (choices.isEmpty || g.progress.stockRoom <= 0) break;
          if (trader) choices.sort((a, b) => (b.$2['ask'] as num).compareTo(a.$2['ask'] as num));
          final (st, it) = trader ? choices.first : choices[rnd.nextInt(choices.length)];
          final r = await haggle(g, '${st['id']}', '${it['id']}');
          if (r['result'] == 'short') short = true;
        }
        // sell at your own stall: ask the usual price, else take their offer
        for (var k = 0; k < (trader ? 10 : 3) && g.progress.stock.isNotEmpty; k++) {
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
        // the shop: the cheapest thing not yet owned, as soon as the jar (and, with a wallet, Save & buy) allows
        for (final gl in [...goals]..sort((a, b) => a.cost.compareTo(b.cost))) {
          if (g.progress.owns(gl.id)) continue;
          final have = g.progress.jar + (wallet ? g.progress.wallet - 30 : 0); // (keeps $30 to shop with)
          if (have < gl.cost) break;
          await g.buyGoal(gl.id, fromWallet: wallet);
          got.putIfAbsent(gl.id, () => []).add(d);
        }
        day = day.add(const Duration(days: 1));
      }
    }
    String when(List<int> days) => days.isEmpty
        ? 'never'
        : 'day ${(days.reduce((a, b) => a + b) / days.length).toStringAsFixed(1)} on average '
              '(${days.length}/$players players)';
    stdout.writeln(
      wallet
          ? '\n👛 WITH THE WALLET, ${trader
                ? 'a money-maker: the priciest things, as many as fit'
                : chase
                ? 'buying every legendary item'
                : 'saving for the jar goals instead'}'
          : '🫙 WITHOUT (as now)',
    );
    for (final id in const ['cake', 'awning', 'scooter', 'storeroom', 'van', 'stall2', 'wall']) {
      final gl = goals.firstWhere((x) => x.id == id);
      stdout.writeln('  ${gl.emoji} ${gl.name} (\$${gl.cost.toInt()}): ${when(got[id] ?? const [])}');
    }
    stdout.writeln(
      '  shop items owned by the end: ${(got.values.fold<int>(0, (a, b) => a + b.length) / players).toStringAsFixed(1)} of ${goals.length}',
    );
    stdout.writeln('  legendary: bought $legendBought of $legendDays tries');
    stdout.writeln('  legendary results: $why');
    stdout.writeln('  short examples: ${shortBy.take(6).join('; ')}');
    stdout.writeln('  days a purchase was out of reach: $shortDays of ${days * players}');
    if (wallet) {
      stdout.writeln('  wallet: lowest \$${minWallet.toStringAsFixed(2)}, highest \$${maxWallet.toStringAsFixed(2)}');
    }
  }
}
