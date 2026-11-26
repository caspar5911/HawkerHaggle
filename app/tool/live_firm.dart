// A short live check of a best price given too early: her words (her best price for you, never "my real floor" or
// "cost price") and what she says when you win her over and she comes down again. One call at a time.
// Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_firm.dart
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
  final untrue = RegExp(r'\b(floor|cost price|real lowest|lowest price|capital)\b', caseSensitive: false);
  for (final (stall, item, low, spot) in const [
    ('raj', 'powerbank', 20, 'boss you watch the cricket last night?'),
    ('mei', 'durian', 17, 'auntie you play mahjong this weekend?'),
    ('lim', 'prawns', 14, 'uncle you still go fishing?'),
  ]) {
    final g = Game(
      content: content,
      store: MemoryKeyValue(),
      ai: AiClient(cfg, log: rejected.add),
      surprises: false,
      unlockAll: true,
      random: math.Random(5),
    );
    await g.load();
    final w = await g.start('boy', 'yoyo', 'none'); // the first haggle is the gentle one: get it out of the way
    await g.move(w['id'] as String, move: 'buy');
    final r = await g.start(stall, item, 'none');
    final id = r['id'] as String;
    await g.move(id, text: '\$$low can?');
    final same = await g.move(id, text: '\$$low can?'); // the same number again: she holds, nothing locked
    stdout.writeln(
      '$stall same: ${same['event']} ask ${same['ask']} ${same['ai_line'] == true ? '✨' : '  '} ${same['line']}',
    );
    if (same['event'] != 'same_offer') fails.add('$stall: repeating the number gave ${same['event']}');
    if (same['ai_line'] != true) fails.add('$stall: no AI line for the same offer');
    final x = await g.move(id, text: 'I only have \$$low');
    stdout.writeln('$stall best: ${x['event']} ask ${x['ask']} ${x['ai_line'] == true ? '✨' : '  '} ${x['line']}');
    if (x['event'] != 'budget_best') {
      stdout.writeln('   (no best price this time: ${x['event']})');
      continue;
    }
    if (x['ai_line'] != true) fails.add('$stall: no AI line for the best price');
    if (untrue.hasMatch('${x['line']}')) fails.add('$stall: calls it her floor or cost: ${x['line']}');
    final y = await g.move(id, text: spot);
    stdout.writeln('$stall reopen: ${y['event']} ask ${y['ask']} ${y['ai_line'] == true ? '✨' : '  '} ${y['line']}');
    if ((y['ask'] as num) >= (x['ask'] as num)) fails.add('$stall: the soft spot did not reopen the price');
    if (y['ai_line'] != true) fails.add('$stall: no AI line when won over');
    if (!'${y['line']}'.contains('\$${_money(y['ask'] as num)}')) {
      stdout.writeln('   (soft: the reply does not say the new price)');
    }
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

String _money(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);
