// A short live check of what stallholders remember: your last visit, gossip about a hard bargain elsewhere, and
// poking them twice. Each greeting with a note is followed by an offer, to see her price stays the game's.
// One call at a time (the GX10 is shared). Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_memory.dart
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
  Future<Game> game(KeyValue store, DateTime day, int seed) async {
    final g = Game(
      content: content,
      store: store,
      ai: AiClient(cfg, log: rejected.add),
      surprises: false,
      unlockAll: true,
      random: math.Random(seed),
      now: () => day,
    );
    await g.load();
    return g;
  }

  String show(Map r) => '${r['event']} ask ${r['ask']} ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}';
  Future<void> greetAndOffer(String what, Game g, String stall, String item, List<String> words) async {
    final r = await g.start(stall, item, 'none');
    stdout.writeln('$what greet: ${show(r)}');
    if (r['ai_line'] != true) fails.add('$what: no AI greeting');
    if (!words.any('${r['line']}'.toLowerCase().contains)) stdout.writeln('   (soft: none of $words)');
    final offer = ((r['ask'] as num) * 0.7).round();
    final o = await g.move(r['id'] as String, text: '$offer can?');
    stdout.writeln('$what offer $offer: ${show(o)}');
    if (o['ai_line'] != true) fails.add('$what: no AI reply to the offer after a note');
  }

  final day1 = DateTime(2026, 12, 2, 10), day2 = DateTime(2026, 12, 3, 10);

  // walked away yesterday
  {
    final store = MemoryKeyValue();
    final g = await game(store, day1, 1);
    final r = await g.start('lim', 'pomfret', 'none');
    await g.move(r['id'] as String, move: 'walk');
    await greetAndOffer('WALKED', await game(store, day2, 2), 'lim', 'pomfret', ['back', 'again', 'yesterday', 'walk']);
  }
  // rude yesterday
  {
    final store = MemoryKeyValue();
    await store.write(
      'profile',
      jsonEncode({
        'name': 'Tester',
        'haggles': [
          {'stall': 'raj', 'item': 'case', 'result': 'refused', 'rude': true, 'stars': 0, 'day': '2026-12-02'},
        ],
      }),
    );
    await greetAndOffer('RUDE', await game(store, day2, 3), 'raj', 'case', [
      'rude',
      'yesterday',
      'remember',
      'manners',
    ]);
  }
  // gossip: a hard bargain at Uncle Lim's yesterday (about one greeting in two mentions it)
  for (var k = 0; k < 3; k++) {
    final store = MemoryKeyValue();
    await store.write(
      'profile',
      jsonEncode({
        'name': 'Tester',
        'haggles': [
          {'stall': 'lim', 'item': 'pomfret', 'result': 'deal', 'deal': 13, 'stars': 3, 'day': '2026-12-02'},
        ],
      }),
    );
    final g = await game(store, day2, 10 + k);
    final r = await g.start('mei', 'mango', 'none');
    stdout.writeln('GOSSIP $k greet: ${show(r)}');
    if (r['ai_line'] != true) continue; // no note this time: a ready-made greeting is fine
    final o = await g.move(r['id'] as String, text: '\$11 can?');
    stdout.writeln('GOSSIP $k offer: ${show(o)}');
    if (o['ai_line'] != true) fails.add('gossip $k: no AI reply to the offer');
  }
  // poking twice
  for (final (stall, item, a, b) in const [
    ('mei', 'mango', 'auntie you so pretty, date me', 'come on auntie, just one date lah'),
    ('raj', 'powerbank', 'you cheat people one', 'cheater lah you'),
  ]) {
    final g = await game(MemoryKeyValue(), day1, 20);
    final r = await g.start(stall, item, 'none');
    final id = r['id'] as String;
    var x = await g.move(id, text: a);
    stdout.writeln('POKE $stall 1: ${show(x)}');
    if (x['done'] == true) continue;
    x = await g.move(id, text: b);
    stdout.writeln('POKE $stall 2: ${show(x)}');
    if (x['ai_line'] != true && x['done'] != true) fails.add('$stall: no AI reply to the second poke');
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
