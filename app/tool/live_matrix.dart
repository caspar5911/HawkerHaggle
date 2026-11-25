// Live check of the app's own game code against a real AI endpoint (not run by `flutter test`).
//   AI_ENDPOINT=https://host/v1 AI_MODEL=name [AI_KEY=...] dart run tool/live_matrix.dart [report.md]
// Same cases as server/tests/live_matrix.py (exported to tool/live_cases.json).
import 'dart:convert';
import 'dart:io';

import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/progress.dart' show dayKey;

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
    surprises: false, // the base cases need plain haggles
    unlockAll: true,
  );
  await game.load();
  const stalls = ['mei', 'lim', 'raj', 'siti'];
  const items = {'mei': 'durian', 'lim': 'pomfret', 'raj': 'powerbank', 'siti': 'scarf'};
  final rows = <String>[];
  final fails = <String>[];
  final times = <double>[];
  final fastTimes = <double>[];
  var aiLines = 0;
  final onlyNew = (env['ONLY_NEW'] ?? '').isNotEmpty; // re-check just the newer features
  final cases = onlyNew ? const [] : spec['cases'] as List;
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
    final own = [r['ask'], r['deal'], r['pending']].whereType<num>().map((v) => v.toDouble()).toList();
    final said = [for (final m in RegExp(r'\$\s*(\d+(?:\.\d+)?)').allMatches('${r['line']}')) double.parse(m[1]!)];
    if (said.isNotEmpty && r['event'] != 'clarify' && !said.any((a) => own.any((o) => (o - a).abs() < 0.001))) {
      problems.add('mentions a price but not her real one (${own.join('/')})');
    }
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
  final facts = onlyNew ? const {} : spec['facts'] as Map;
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
  // walking away: a friendly, close haggle can get a final-final price; a rude lowballer never does
  var callbacks = 0;
  for (var k = 0; k < 4; k++) {
    final stall = stalls[k];
    final g = await game.start(stall, items[stall]);
    final id = g['id'] as String;
    final ask = (g['ask'] as num).toDouble();
    await game.move(id, text: 'wah ${stall == 'raj' ? 'boss' : 'so nice'}, everything look so good today');
    await game.move(id, text: '${(ask * 0.85).round()} can?');
    final r = await game.move(id, move: 'walk');
    stdout.writeln('WALK  friendly $stall -> ${r['event']}: ${r['line']}');
    if (r['event'] == 'callback') {
      callbacks++;
      if (!finalWords.hasMatch('${r['line']}') && !'${r['line']}'.toLowerCase().contains('last')) {
        fails.add('callback for $stall did not say it is the final price: ${r['line']}');
      }
      final again = await game.move(id, move: 'walk');
      if (again['event'] != 'letgo') fails.add('walking again after a final-final price did not end it ($stall)');
    }
    final g2 = await game.start(stall, items[stall]);
    await game.move(g2['id'] as String, text: 'your stuff rubbish, you cheat people');
    await game.move(g2['id'] as String, text: '${(ask * 0.3).round()}');
    final r2 = await game.move(g2['id'] as String, move: 'walk');
    stdout.writeln('WALK  rude $stall -> ${r2['event']}: ${r2['line']}');
    if (r2['event'] == 'callback') fails.add('called back a rude lowballer ($stall)');
  }
  stdout.writeln('friendly walk-aways called back: $callbacks/4');
  if (callbacks == 0) fails.add('no friendly, close walk-away was ever called back');
  // taps are messages: an AI-written reply
  final gt = await game.start('siti', 'kueh');
  final rt = await game.move(gt['id'] as String, pick: 2);
  stdout.writeln('TAP   ${rt['you_said']} -> ${rt['event']} ${rt['ai_line'] == true ? '✨' : '  '} ${rt['line']}');
  if (rt['ai_line'] != true) fails.add('a tapped suggestion did not get an AI reply');

  // festival weeks (real dates): the greeting wishes the customer, and still names no price the game didn't give
  for (final (day, words) in [
    (DateTime(2027, 2, 4, 9), ['new year', 'gong xi', 'huat', 'cny', 'prosper']),
    (DateTime(2026, 12, 23, 9), ['christmas', 'xmas']),
  ]) {
    final fg = Game(content: content, store: MemoryKeyValue(), ai: AiClient(cfg), now: () => day, unlockAll: true);
    await fg.load();
    final g = await fg.start('mei', 'mango', 'festival');
    final said = '${g['line']}'.toLowerCase();
    final wished = words.any(said.contains);
    stdout.writeln('FEST  ${fg.festivalWeek?.name} ${g['ai_line'] == true ? '✨' : '  '} wished=$wished ${g['line']}');
    if (g['ai_line'] != true) fails.add('no AI greeting in ${fg.festivalWeek?.name} week');
    if (!wished) fails.add('the ${fg.festivalWeek?.name} greeting did not mention the festival');
  }

  // gossip: a friend came by (named, never priced); rude next door today
  {
    final gg = Game(content: content, store: MemoryKeyValue(), ai: AiClient(cfg), surprises: false, unlockAll: true);
    await gg.load();
    gg.gossip = {
      'mei': [
        {'name': 'Arella', 'item': 'durian', 'day': dayKey(DateTime.now())},
      ],
    };
    final g = await gg.start('mei', 'mango', 'none');
    final named = '${g['line']}'.toLowerCase().contains('arella');
    stdout.writeln('GOSS  friend ${g['ai_line'] == true ? '✨' : '  '} named=$named ${g['line']}');
    if (g['ai_line'] != true) fails.add('no AI greeting with a friend\'s gossip');
    if (!named) fails.add('the gossip greeting did not name the friend');
    final x = await gg.start('lim', 'pomfret', 'none');
    var y = await gg.move(x['id'] as String, text: 'you stupid old man');
    for (var i = 0; i < 10 && y['done'] != true; i++) {
      y = await gg.move(x['id'] as String, move: 'walk');
    }
    final r = await gg.start('siti', 'kueh', 'none');
    stdout.writeln('GOSS  rude ${r['ai_line'] == true ? '✨' : '  '} ${r['line']}');
    if (r['ai_line'] != true) fails.add('no AI greeting after rudeness next door');
  }

  // market surprises: the greeting reflects them; Auntie Rose can win
  for (final ev in ['rain', 'closing', 'festival', 'rival']) {
    final g = await game.start('mei', 'mango', ev);
    stdout.writeln('SURPR $ev ${g['ai_line'] == true ? '✨' : '  '} ${g['line']}');
    if (g['ai_line'] != true) fails.add('no AI greeting for the $ev surprise');
    if (ev == 'rival') {
      Map r = g;
      for (var i = 0; i < 4 && r['done'] != true; i++) {
        r = await game.move(g['id'] as String, text: "auntie how's business today?");
      }
      stdout.writeln('RIVAL ${r['result']} ${r['event']}: ${r['line']}');
      if (r['result'] != 'lost') fails.add('Auntie Rose never bought it');
    }
  }
  // a friend is greeted like a friend (a fresh player: the checks above were rude to some stallholders)
  final friendGame = Game(content: content, store: MemoryKeyValue(), ai: AiClient(cfg), surprises: false);
  await friendGame.load();
  await friendGame.setName('Jing Qi'); // a name the player picked
  for (var i = 0; i < 2; i++) {
    final g = await friendGame.start('lim', 'pomfret', 'none');
    await friendGame.move(g['id'] as String, move: 'buy');
  }
  final fg = await friendGame.start('lim', 'pomfret', 'none');
  stdout.writeln('FRIEND hearts ${fg['hearts']} ${fg['ai_line'] == true ? '✨' : '  '} ${fg['line']}');
  if (fg['ai_line'] != true) fails.add('a friend did not get an AI greeting');
  stdout.writeln('FRIEND greeting uses the chosen name: ${'${fg['line']}'.contains('Jing Qi')}');
  // the new stalls, in their own voices, with true facts
  for (final (st, it, q, words) in [
    ('lee', 'oolong', 'where is this tea from?', ['anxi', 'fujian', 'tie guan yin']),
    ('boy', 'rccar', 'bro how long the battery last?', ['20', 'minute']),
    ('wong', 'radio', 'uncle how old is this radio?', ['1970', 'seventies', '70s']),
    ('kumar', 'saffron', 'is this real saffron?', ['kashmir', 'golden', 'real']),
    ('rosnah', 'tray', 'makcik what comes in each packet?', ['chicken', 'egg', 'ikan bilis', 'sambal']),
    ('faiz', 'sneakers', 'bro what size is this?', ['9', 'uk']),
    ('tan', 'bicycle', 'ah ma what time must I return the bike?', ['6', 'six']),
  ]) {
    final g = await game.start(st, it, 'none');
    final r = await game.move(g['id'] as String, text: q);
    final hit = words.any((w) => '${r['line']}'.toLowerCase().contains(w));
    stdout.writeln('NEW   $st ${hit ? 'ok  ' : 'MISS'} ${r['line']}');
    if (!hit) fails.add('$st facts: ${r['line']}');
    final o = await game.move(g['id'] as String, text: '15 can?');
    stdout.writeln('NEW   $st offer -> ${o['event']}: ${o['line']}');
  }

  if (times.isEmpty) times.add(0);
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
