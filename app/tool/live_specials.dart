// A live check of the weekly specials: for each one, ask about it and make an offer. The stallholder must answer with
// an AI line (not a fallback), keep the game's price on a question, and the offer must be read right.
// One call at a time (the GX10 is shared).
// Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_specials.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/specials.dart';

Future<void> main() async {
  final env = Platform.environment;
  final cfg = AiConfig(endpoint: env['AI_ENDPOINT'] ?? '', model: env['AI_MODEL'] ?? '', apiKey: env['AI_KEY'] ?? '');
  if (!cfg.enabled) {
    stderr.writeln('Set AI_ENDPOINT (and AI_MODEL) first.');
    exit(2);
  }
  final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;
  final fails = <String>[], soft = <String>[], rejected = <String>[];
  for (final MapEntry(key: st, value: list) in specials.entries) {
    for (final x in list) {
      final day = [for (var w = 0; w < 2; w++) DateTime(2026, 12, 2 + 7 * w, 10)]
          .firstWhere((d) => specialFor(st, d)?['id'] == x['id']);
      final g = Game(
        content: content,
        store: MemoryKeyValue(),
        ai: AiClient(cfg, log: rejected.add),
        surprises: false,
        unlockAll: true,
        walletOn: false,
        random: math.Random(5),
        now: () => day,
      );
      await g.load();
      final w = await g.start('boy', 'yoyo', 'none'); // (the first haggle is the gentle one)
      await g.move(w['id'] as String, move: 'buy');
      final r0 = await g.start(st, '${x['id']}', 'none');
      final id = r0['id'] as String;
      final ask0 = r0['ask'];
      final q = await g.move(id, text: 'Where is this from? Is it good?');
      final offer = (((x['fair'] as num) * 0.85) * 2).round() / 2;
      final o = await g.move(id, text: '\$${offer == offer.roundToDouble() ? offer.toInt() : offer} can?');
      stdout.writeln('$st/${x['id']} (ask \$$ask0)');
      stdout.writeln('   Q ${q['event']} ask ${q['ask']} ${q['ai_line'] == true ? '✨' : '  '} ${q['line']}');
      stdout.writeln('   O ${o['event']} ask ${o['ask']} ${o['ai_line'] == true ? '✨' : '  '} ${o['line']}');
      if (q['ai_line'] != true) fails.add('$st/${x['id']}: no AI line for a question');
      if (o['ai_line'] != true) fails.add('$st/${x['id']}: no AI line for an offer');
      if (q['ask'] != ask0) fails.add('$st/${x['id']}: the price moved on a question');
      if (!{'counter', 'final', 'accept', 'confirm'}.contains(o['event'])) {
        soft.add('$st/${x['id']}: an offer of \$$offer read as ${o['event']}');
      }
    }
  }
  stdout.writeln('\nLines rejected and retried: ${rejected.length}');
  for (final x in rejected) {
    stdout.writeln('REJECTED: $x');
  }
  for (final s in soft) {
    stdout.writeln('SOFT: $s');
  }
  stdout.writeln('${fails.length} failures, ${soft.length} soft misses.');
  for (final f in fails) {
    stdout.writeln('FAIL: $f');
  }
  exit(fails.isEmpty ? 0 : 1);
}
