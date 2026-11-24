// Live check of the app's own game code against a real AI endpoint (not run by `flutter test`).
//   AI_ENDPOINT=https://host/v1 AI_MODEL=name [AI_KEY=...] dart run tool/live_matrix.dart [report.md]
// Same cases as server/tests/live_matrix.py (exported to tool/live_cases.json).
import 'dart:convert';
import 'dart:io';

import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/game.dart';

final finalWords = RegExp(
  r"\b(final|last price|lowest|rock bottom|cannot go lower|can't go lower)\b",
  caseSensitive: false,
);

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final cfg = AiConfig(endpoint: env['AI_ENDPOINT'] ?? '', model: env['AI_MODEL'] ?? '', apiKey: env['AI_KEY'] ?? '');
  if (!cfg.enabled) {
    stderr.writeln('Set AI_ENDPOINT (and AI_MODEL) first.');
    exit(2);
  }
  final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map;
  final spec = jsonDecode(File('tool/live_cases.json').readAsStringSync()) as Map;
  final rejected = <String>[];
  final game = Game(
    content: content,
    store: MemoryKeyValue(),
    ai: AiClient(cfg, log: rejected.add),
  );
  await game.load();
  const stalls = ['mei', 'lim', 'raj', 'siti'];
  const items = {'mei': 'durian', 'lim': 'pomfret', 'raj': 'powerbank', 'siti': 'scarf'};
  final rows = <String>[];
  final fails = <String>[];
  final times = <double>[];
  final fastTimes = <double>[];
  var aiLines = 0;
  final cases = spec['cases'] as List;
  for (var i = 0; i < cases.length; i++) {
    var msg = cases[i][0] as String;
    final moment = cases[i][1] as String;
    final ok = {...(cases[i][2] as List).cast<String>()};
    final stall = stalls[i % 4];
    var g = await game.start(stall, items[stall]);
    num? pending;
    if (moment == 'pending') {
      g = await game.move(g['id'] as String, move: 'accept');
      pending = g['pending'] as num;
      final p = pending.toDouble();
      String f(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
      msg = msg.replaceAll('PENDING-2', f(p - 2)).replaceAll(r'$PENDING', '\$${f(p)}').replaceAll('PENDING', f(p));
    }
    final sw = Stopwatch()..start();
    final r = await game.move(g['id'] as String, text: msg);
    final secs = sw.elapsedMilliseconds / 1000;
    times.add(secs);
    if (RegExp(r'^\$?\d+(\.\d+)?( can\?| lah)?$').hasMatch(msg)) fastTimes.add(secs);
    final you = game.lastYou(g['id'] as String) ?? {};
    var move = '${you['move']}';
    if (move == 'confirm') move = 'accept';
    final problems = <String>[];
    if (!ok.contains(move)) problems.add('read as $move, expected ${ok.toList()..sort()}');
    final priceAgain =
        moment == 'pending' &&
        RegExp(r'^\$?\d+(\.\d+)?$').hasMatch(msg.trim()) &&
        double.parse(msg.trim().replaceAll(r'$', '')) >= pending!;
    if (r['done'] == true && r['result'] == 'deal' && moment != 'pending') {
      problems.add('closed a deal without a confirm step');
    }
    if (moment == 'pending' && move == 'accept' && r['result'] != 'deal') {
      problems.add('a yes to a waiting deal did not close it');
    }
    if (moment == 'pending' && move != 'accept' && r['result'] == 'deal' && !priceAgain) {
      problems.add('closed a deal on a non-yes');
    }
    if (['counter', 'plead', 'confirm', 'flattered', 'regular', 'competitor_drop'].contains(r['event']) &&
        finalWords.hasMatch('${r['line']}')) {
      problems.add("says 'final/lowest' when it isn't");
    }
    if (r['event'] == 'confirm' && !'${r['line']}'.contains('?')) problems.add("confirm line doesn't ask for a yes");
    if (msg == 'wah so nice, 20 can?' && you['also'] != 'compliment') problems.add('missed the compliment');
    if (msg.startsWith('I love you auntie') && !['flirt', 'compliment'].contains(you['also'])) {
      problems.add('missed the flirt');
    }
    if (move == 'flirt' && r['event'] != 'deflect') problems.add('flirt not deflected');
    if (r['ai_line'] == true) aiLines++;
    final hard = problems.isNotEmpty;
    if (hard) fails.add('$moment "$msg": ${problems.join('; ')}');
    final line = '${r['line']}';
    stdout.writeln(
      '${hard ? 'FAIL' : 'ok  '} ${secs.toStringAsFixed(1).padLeft(4)}s $moment '
      '${'"$msg"'.padRight(44).substring(0, 44)} -> ${move.padRight(10)} ${'${r['event']}'.padRight(16)} '
      '${r['ai_line'] == true ? '✨' : '  '} ${line.length > 90 ? line.substring(0, 90) : line}',
    );
    rows.add(
      '| $moment | ${msg.replaceAll('|', r'\|')} | $move | ${r['event']} | ${r['ai_line'] == true ? '✨' : ''} | '
      '${secs.toStringAsFixed(1)} | ${line.replaceAll('|', r'\|')} | ${problems.join('; ')} |',
    );
  }
  // facts: the same question in two haggles gets the same true answer
  final facts = spec['facts'] as Map;
  for (final e in facts.entries) {
    final item = e.value[0] as String, q = e.value[1] as String;
    final words = (e.value[2] as List).cast<String>();
    for (var k = 0; k < 2; k++) {
      final g = await game.start(e.key as String, item);
      final r = await game.move(g['id'] as String, text: q);
      final hit = words.any((w) => '${r['line']}'.toLowerCase().contains(w));
      stdout.writeln('FACT  ${e.key} #${k + 1} ${hit ? 'ok  ' : 'MISS'} ${r['line']}');
      if (!hit) fails.add('facts ${e.key}: ${r['line']}');
    }
  }
  times.sort();
  fastTimes.sort();
  final summary =
      '${cases.length} messages, ${fails.length} failures. AI wrote $aiLines/${cases.length} replies. '
      'Reply time median ${times[times.length ~/ 2].toStringAsFixed(1)}s, slowest ${times.last.toStringAsFixed(1)}s'
      '${fastTimes.isEmpty ? '' : ', plain offers ${fastTimes[fastTimes.length ~/ 2].toStringAsFixed(1)}s'}. '
      'Lines rejected and retried: ${rejected.length}.';
  stdout.writeln('\n$summary');
  for (final f in fails) {
    stdout.writeln('FAIL: $f');
  }
  if (args.isNotEmpty) {
    File(args.first).writeAsStringSync(
      '# Live check (app code)\n\n$summary\n\n'
      '| moment | message | read as | event | AI | s | reply | problems |\n|---|---|---|---|---|---|---|---|\n'
      '${rows.join('\n')}\n',
    );
  }
  exit(fails.isEmpty ? 0 : 1);
}
