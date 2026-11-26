// Live check of every legendary item (the rotation and the festival specials) against the real model: an AI
// greeting, and a question about the item answered with its true facts. One call at a time (the GX10 is shared).
// Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_legends.dart
import 'dart:convert';
import 'dart:io';

import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/legendary.dart';
import 'package:hawker_haggle/core/progress.dart' show dayKey;

Future<void> main() async {
  final env = Platform.environment;
  final cfg = AiConfig(endpoint: env['AI_ENDPOINT'] ?? '', model: env['AI_MODEL'] ?? '', apiKey: env['AI_KEY'] ?? '');
  if (!cfg.enabled) {
    stderr.writeln('Set AI_ENDPOINT (and AI_MODEL) first.');
    exit(2);
  }
  final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map;
  final fails = <String>[];
  final rejected = <String>[];
  final today = dayKey(DateTime.now());
  var n = 0, greeted = 0, facts = 0;
  for (final e in legendaryByStall.entries) {
    for (final item in e.value) {
      n++;
      final g = Game(
        content: content,
        store: MemoryKeyValue(),
        ai: AiClient(cfg, log: rejected.add),
        surprises: false,
        unlockAll: true,
      );
      await g.load();
      g.legendEvents = cleanEvents(
        [
          {'id': n, 'stall': e.key, 'from': today, 'to': today, 'item': item},
        ],
        {e.key},
      );
      var r = await g.start(e.key, 'legend_evt_$n');
      if (r['ai_line'] == true) greeted++;
      stdout.writeln('GREET ${item['id']} ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}');
      if (r['ai_line'] != true) fails.add('${item['id']}: no AI greeting');
      r = await g.move(r['id'] as String, text: 'wah, tell me more about this one, where is it from?');
      // a word from its facts or name (the first five letters, so "Lanka" counts for "Lankan")
      final words = {
        for (final f in [...(item['facts'] as List).cast<String>(), '${item['name']}'])
          for (final w in f.toLowerCase().split(RegExp(r"[^a-z0-9']+")))
            if (w.length >= 5) w.substring(0, 5),
      };
      final hit = words.any('${r['line']}'.toLowerCase().contains);
      if (hit) facts++;
      stdout.writeln('FACT  ${item['id']} ${hit ? 'ok  ' : 'MISS'} ${r['line']}');
      if (!hit) fails.add('${item['id']} facts: ${r['line']}');
    }
  }
  stdout.writeln(
    '\n$n items: $greeted AI greetings, $facts answered with their facts. Lines rejected: ${rejected.length}',
  );
  for (final x in rejected) {
    stdout.writeln('REJECTED: $x');
  }
  stdout.writeln('${fails.length} failures.');
  for (final f in fails) {
    stdout.writeln('FAIL: $f');
  }
  exit(fails.isEmpty ? 0 : 1);
}
