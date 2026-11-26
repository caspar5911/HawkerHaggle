// A short live check of an offer far too low: she must sound offended (not just "not enough"), in character, and her
// price stays the game's. One call at a time (the GX10 is shared).
// Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_offended.dart
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
  final soft = <String>[];
  final rejected = <String>[];
  final offended = RegExp(
    r'insult|offend|joking|kidding|cheek|crazy|siao|faint|cry|robb|steal|bankrupt|serious|how can|cannot be|wah lau|aiyo|aduh|haiz|alamak|you think|play play',
    caseSensitive: false,
  );
  for (final (stall, item, low) in const [
    ('rosnah', 'tray', 20),
    ('mei', 'durian', 8),
    ('lim', 'prawns', 7),
    ('raj', 'powerbank', 10),
    ('wong', 'radio', 15),
    ('siti', 'scarf', 9),
  ]) {
    final g = Game(
      content: content,
      store: MemoryKeyValue(),
      ai: AiClient(cfg, log: rejected.add),
      surprises: false,
      unlockAll: true,
      walletOn: false,
      random: math.Random(4),
    );
    await g.load();
    final w = await g.start('boy', 'yoyo', 'none'); // (the first haggle is the gentle one)
    await g.move(w['id'] as String, move: 'buy');
    final r0 = await g.start(stall, item, 'none');
    final r = await g.move(r0['id'] as String, text: '\$$low can?');
    final line = '${r['line']}';
    stdout.writeln('$stall \$$low -> ${r['event']} ask ${r['ask']} ${r['ai_line'] == true ? '✨' : '  '} $line');
    if (r['event'] != 'insulted') fails.add('$stall: \$$low was ${r['event']}, not an insult');
    if (r['ai_line'] != true) fails.add('$stall: no AI line');
    if (r['ask'] != r0['ask']) fails.add('$stall: the price moved on an insult');
    if (!offended.hasMatch(line)) soft.add('$stall: may not sound offended: $line');
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
