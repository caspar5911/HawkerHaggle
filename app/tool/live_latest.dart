// A short live check of the newest AI-facing parts against the real model: legendary items (their greeting, their
// true facts, prices only from the game) and a co-op tag-team combo. One call at a time (the GX10 is shared).
// Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_latest.dart
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
  DateTime dayFor(String stall) {
    for (var d = DateTime(2026, 12, 1, 10); ; d = d.add(const Duration(days: 1))) {
      if (legendaryOn(dayKey(d))?.stall == stall) return d;
    }
  }

  // legendary items: an AI greeting that sounds proud, a true fact when asked, and the game's prices only
  for (final (stall, q, words) in [
    ('mei', 'auntie where is this durian from?', ['raub', 'pahang', 'tree']),
    ('lim', 'uncle who caught this fish?', ['ubin', 'friend', 'morning']),
    ('wong', 'uncle where is this compass from?', ['ship', 'penang', '1950']),
    ('faiz', 'bro who signed these boots?', ['national', 'player', 'stadium']),
  ]) {
    final day = dayFor(stall);
    final g = Game(
      content: content,
      store: MemoryKeyValue(),
      ai: AiClient(cfg, log: rejected.add),
      surprises: false,
      unlockAll: true,
      now: () => day,
    );
    await g.load();
    final item = legendaryOn(dayKey(day))!.item;
    var r = await g.start(stall, item['id'] as String);
    stdout.writeln('LEGEND $stall greet ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}');
    if (r['ai_line'] != true) fails.add('$stall: no AI greeting for the legendary item');
    final id = r['id'] as String;
    r = await g.move(id, text: q);
    final hit = words.any('${r['line']}'.toLowerCase().contains);
    stdout.writeln('LEGEND $stall fact ${hit ? 'ok  ' : 'MISS'} ${r['line']}');
    if (!hit) fails.add('$stall legendary facts: ${r['line']}');
    final offer = ((item['ask'] as num) * 0.7).round();
    r = await g.move(id, text: '$offer can?');
    stdout.writeln(
      'LEGEND $stall offer $offer -> ${r['event']} ask ${r['ask']} ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}',
    );
    if (r['ai_line'] != true) fails.add('$stall: no AI reply to an offer on the legendary item');
  }

  // a tag-team combo: one friend sweet-talks, the other offers; the reply notices the teamwork
  {
    final g = Game(
      content: content,
      store: MemoryKeyValue(),
      ai: AiClient(cfg, log: rejected.add),
      surprises: false,
      unlockAll: true,
    );
    await g.load();
    var r = await g.start('mei', 'mango', 'none');
    final id = r['id'] as String;
    r = await g.move(id, text: 'wah auntie your mangoes look so sweet today!');
    stdout.writeln('COMBO  sweet ${r['event']} ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}');
    r = await g.move(id, text: '\$12 can?', friend: 'Melody');
    final noticed = ['two', 'both', 'team', 'together', 'friend', 'melody'].any('${r['line']}'.toLowerCase().contains);
    stdout.writeln(
      'COMBO  offer combo=${r['combo']} ${r['event']} ask ${r['ask']} noticed=$noticed ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}',
    );
    if (r['combo'] != true) fails.add('the combo did not happen');
    if (r['ai_line'] != true) fails.add('no AI reply to a combo');
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
