// A short live check of "buy two" against the real model: one-of-a-kind items ("only got one"), prices that say
// "each" while buying two, and changing your mind back to one. One call at a time (the GX10 is shared).
// Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_two.dart
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
  final soft = <String>[]; // the reply is fine but didn't use the word we hoped for
  final rejected = <String>[];
  Future<Game> game([DateTime? day]) async {
    final g = Game(
      content: content,
      store: MemoryKeyValue(),
      ai: AiClient(cfg, log: rejected.add),
      surprises: false,
      unlockAll: true,
      now: day == null ? null : () => day,
    );
    await g.load();
    return g;
  }

  String show(Map r) =>
      '${r['event']} qty ${r['qty']} ask ${r['ask']} ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}';
  void expectEvent(String what, Map r, String event) {
    stdout.writeln('$what: ${show(r)}');
    if (r['event'] != event) fails.add('$what: wanted $event, got ${r['event']}');
    if (r['ai_line'] != true) fails.add('$what: no AI line');
  }

  // one of a kind: "two" gets "only got one", the price unchanged
  for (final (stall, item, text) in const [
    ('wong', 'radio', 'uncle if I buy two, can cheaper?'),
    ('faiz', 'sneakers', 'bro I take two pairs, special price?'),
    ('siti', 'scarf', 'kak, two scarves for \$50 can?'),
  ]) {
    final g = await game();
    final r0 = await g.start(stall, item, 'none');
    final r = await g.move(r0['id'] as String, text: text);
    expectEvent('ONE-OF-A-KIND $stall', r, 'only_one');
    if (r['ask'] != r0['ask']) fails.add('$stall: the price moved on "two"');
    if (!RegExp(r'\b(one|only|1)\b', caseSensitive: false).hasMatch('${r['line']}')) {
      soft.add('$stall: did not say there is only one: ${r['line']}');
    }
  }
  {
    var day = DateTime(2026, 12, 1, 10);
    while (legendaryOn(dayKey(day)) == null) {
      day = day.add(const Duration(days: 1));
    }
    final l = legendaryOn(dayKey(day))!;
    final g = await game(day);
    final r0 = await g.start(l.stall, '${l.item['id']}');
    final r = await g.move(r0['id'] as String, text: 'can I buy two of these?');
    expectEvent('LEGENDARY ${l.stall}', r, 'only_one');
  }

  // buying two: "each" on the prices, then back to one
  for (final (stall, item, two, offer, back) in const [
    ('mei', 'mango', 'auntie I take two boxes, can cheaper?', '\$13 each can?', 'actually just one lah, sorry'),
    ('raj', 'case', 'boss two for \$20?', '\$10.50 each lah boss', 'just one, \$11 can?'),
    ('lim', 'prawns', 'uncle I buy 2 packs, discount?', '19 each ok?', "don't want two already, one enough"),
  ]) {
    final g = await game();
    final r0 = await g.start(stall, item, 'none');
    final id = r0['id'] as String;
    var r = await g.move(id, text: two);
    stdout.writeln('TWO $stall: ${show(r)}');
    if (r['qty'] != 2) fails.add('$stall: "$two" did not make it two');
    if (r['ai_line'] != true) fails.add('$stall: no AI line for two');
    if (r['event'] == 'bulk' && !'${r['line']}'.contains('each')) soft.add('$stall: two-piece price without "each"');
    if (r['done'] != true && r['pending'] == null) {
      r = await g.move(id, text: offer);
      stdout.writeln('TWO $stall offer: ${show(r)}');
      if (r['qty'] != 2) fails.add('$stall: the offer changed the count');
      final hasPrice = RegExp(r'\$\d').hasMatch('${r['line']}');
      if (hasPrice && !'${r['line']}'.contains('each')) soft.add('$stall offer: a price without "each": ${r['line']}');
    }
    if (r['pending'] != null) r = await g.move(id, move: 'cancel');
    r = await g.move(id, text: back);
    expectEvent('BACK TO ONE $stall', r, 'back_to_one');
    if (r['qty'] != 1) fails.add('$stall: still two after "$back"');
    if ('${r['line']}'.contains('each')) fails.add('$stall: "each" after going back to one: ${r['line']}');
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
