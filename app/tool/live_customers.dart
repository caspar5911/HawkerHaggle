// A short live check of the stall customers' AI lines (the new ones first): each must get an AI line for greeting,
// bargaining back, a friendly chat, accepting and walking off, in character, with only the game's prices.
// One call at a time (the GX10 is shared).
// Run: AI_ENDPOINT=... AI_MODEL=gx10-current dart run tool/live_customers.dart [all]
import 'dart:io';

import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/shop.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final cfg = AiConfig(endpoint: env['AI_ENDPOINT'] ?? '', model: env['AI_MODEL'] ?? '', apiKey: env['AI_KEY'] ?? '');
  if (!cfg.enabled) {
    stderr.writeln('Set AI_ENDPOINT (and AI_MODEL) first.');
    exit(2);
  }
  final rejected = <String>[];
  final ai = AiClient(cfg, log: rejected.add);
  final who = args.contains('all')
      ? customers
      : customers.where((c) => const {'chef', 'office', 'ahma', 'auntie'}.contains(c.id)).toList();
  const product = Product('lee/scallops', 'packet of dried scallops', '🦪', 42, 58);
  final fails = <String>[];
  final money = RegExp(r'\$\s?(\d+(?:\.\d+)?)');
  Future<void> say(Sale s, String event, List<Map> chat) async {
    final line = await customerSay(ai, s, event, chat);
    final allowed = {s.offer, if (s.ask != null) s.ask!, if (s.price != null) s.price!};
    stdout.writeln('  ${s.customer.id.padRight(7)} ${event.padRight(9)} ${line ?? '(no AI line)'}');
    if (line == null) {
      fails.add('${s.customer.id} $event: no AI line');
      return;
    }
    for (final m in money.allMatches(line)) {
      final v = double.parse(m.group(1)!);
      if (!allowed.any((a) => (a - v).abs() < 0.01)) fails.add('${s.customer.id} $event: a wrong price in "$line"');
    }
    chat.add({'who': 'them', 'text': line});
  }

  for (final c in who) {
    // greet, bargain back, accept (a sale held firm)
    var s = Sale(product, c, seed: 7);
    final chat = <Map>[];
    await say(s, 'greet', chat);
    final near = ((s.most - 0.5) * 2).floor() / 2;
    chat.add({'who': 'you', 'text': '\$$near, can?'});
    final e = s.askFor(near);
    await say(s, e, chat);
    if (!s.done) {
      chat.add({'who': 'you', 'text': '\$$near, can?'});
      await say(s, s.askFor(near), chat);
    }
    // a friendly chat
    s = Sale(product, c, seed: 8);
    final chat2 = <Map>[];
    chat2.add({'who': 'you', 'text': 'You have good taste! 😊'});
    await say(s, s.chat(), chat2);
    // walking off: far too much, again and again
    s = Sale(product, c, seed: 9);
    final chat3 = <Map>[];
    var ev = '';
    while (!s.done) {
      chat3.add({'who': 'you', 'text': '\$${product.fair * 3}, can?'});
      ev = s.askFor(product.fair * 3);
    }
    await say(s, ev, chat3);
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
