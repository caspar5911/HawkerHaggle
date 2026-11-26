// A short live check of how the real model reads numbers people type: percentages, "$5 discount", "cheaper by 3",
// numbers in words, dollars-and-cents, "30 for 2", a count next to a price. Through the whole game, at Auntie Mei's
// mangoes ($18): the offer the game works out must be the one meant. One call at a time (the GX10 is shared).
// Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_numbers.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/game.dart';

Future<void> main() async {
  final env = Platform.environment;
  final cfg = AiConfig(endpoint: env['AI_ENDPOINT'] ?? '', model: env['AI_MODEL'] ?? '', apiKey: env['AI_KEY'] ?? '');
  if (!cfg.enabled) {
    stderr.writeln('Set AI_ENDPOINT (and AI_MODEL) first.');
    exit(2);
  }
  final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;
  final fails = <String>[];
  final rejected = <String>[];
  for (final (text, want) in const [
    ('auntie 10% off can?', 16.0),
    ('can give 10 percent discount or not', 16.0),
    ('25% off lah auntie, I buy every week', 13.5),
    ('half price can?', 9.0),
    ('\$5 discount can?', 13.0),
    ('cheaper by 3 can or not', 15.0),
    ('fifteen lah auntie', 15.0),
    ('I come here 10 years already, 14 can?', 14.0),
    ('15 dollars 50 cents ok?', 15.5),
    ('30 for 2 boxes can?', 15.0),
  ]) {
    final g = Game(
      content: content,
      store: MemoryKeyValue(),
      ai: AiClient(cfg, log: rejected.add),
      surprises: false,
      unlockAll: true,
      random: math.Random(2),
    );
    await g.load();
    final r0 = await g.start('mei', 'mango', 'none');
    final r = await g.move(r0['id'] as String, text: text);
    final got = r['offer'] as num?;
    final ok = got != null && (got - want).abs() < 0.01;
    stdout.writeln(
      '${ok ? 'ok  ' : 'MISS'} "$text" -> ${r['event']} offer $got (want $want) qty ${r['qty']} '
      '${r['ai_line'] == true ? '✨' : '  '} ${r['line']}',
    );
    if (!ok) fails.add('"$text": offer $got, want $want');
    if (r['ai_line'] != true) fails.add('"$text": no AI line');
  }
  // firm words and asking for her lowest, after a first offer of $13
  for (final (text, events) in const [
    ('my final offer 14', ['budget_best', 'confirm']),
    ('take it or leave it auntie, 14', ['budget_best', 'confirm']),
    ('auntie what is your lowest?', ['plead', 'plead_no']),
    ('last price boss?', ['plead', 'plead_no']),
  ]) {
    final g = Game(
      content: content,
      store: MemoryKeyValue(),
      ai: AiClient(cfg, log: rejected.add),
      surprises: false,
      unlockAll: true,
      random: math.Random(2),
    );
    await g.load();
    final r0 = await g.start('mei', 'mango', 'none');
    await g.move(r0['id'] as String, text: '13 can?');
    final r = await g.move(r0['id'] as String, text: text);
    final ok = events.contains(r['event']);
    stdout.writeln(
      '${ok ? 'ok  ' : 'MISS'} "$text" -> ${r['event']} ask ${r['ask']} ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}',
    );
    if (!ok) fails.add('"$text": ${r['event']}, want one of $events');
    if (r['ai_line'] != true) fails.add('"$text": no AI line');
  }
  stdout.writeln('\nLines rejected and retried: ${rejected.length}');
  for (final x in rejected) {
    stdout.writeln('REJECTED: $x');
  }
  stdout.writeln('${fails.length} failures.');
  for (final f in fails) {
    stdout.writeln('FAIL: $f');
  }
  exit(fails.isEmpty ? 0 : 1);
}
