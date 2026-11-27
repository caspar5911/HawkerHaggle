// How selling at your own stall plays (no AI: the customer rules only): is there one customer to wait for? Does selling
// someone what they love pay? Does reading the customer beat pressing buttons?
// Run: dart run tool/selling.dart
import 'dart:math' as math;

import 'package:hawker_haggle/core/shop.dart';

/// One of each kind of thing (what it cost you, its usual price at your stall).
const goods = [
  Product('mango', 'box of mangoes', '🥭', 13, 18), // fresh
  Product('scarf', 'batik scarf', '🧣', 25, 35), // souvenir
  Product('case', 'phone case', '📱', 10, 15), // toy
  Product('lee/scallops', 'dried scallops', '🦪', 42, 58), // premium
];

/// A sale as the game makes it: the customer's love for the thing makes them pay more and open higher.
Sale sale(Product p, Customer c, int seed) {
  final s = Sale(p, c, seed: seed);
  if (c.loves.contains(kindOf(p.id))) {
    s.most = (s.most * loveMore * 2).round() / 2;
    s.offer = math.min(s.most, (s.offer * loveOpens * 2).round() / 2);
  }
  return s;
}

void main() {
  final rnd = math.Random(1);
  // 1. who pays the most? (their limit against the usual price)
  out('Their limit / the usual price (4000 each):');
  for (final c in customers) {
    var all = 0.0, loved = 0.0, nl = 0;
    for (var i = 0; i < 4000; i++) {
      final p = goods[rnd.nextInt(goods.length)];
      final s = sale(p, c, rnd.nextInt(1 << 30));
      all += s.most / p.fair;
      if (c.loves.contains(kindOf(p.id))) {
        loved += s.most / p.fair;
        nl++;
      }
    }
    out(
      '  ${c.id}: ${(all / 4000).toStringAsFixed(2)} on average, ${(loved / math.max(1, nl)).toStringAsFixed(2)} '
      'for what they love (${c.loves.join(', ')})',
    );
  }
  // 2. sellers
  // (what a careful seller guesses from the clue: never their real limit)
  const reads = {
    'taitai': 1.1,
    'tourist': 1.05,
    'uncle': 0.95,
    'student': 0.85,
    'chef': 1.05,
    'office': 0.95,
    'ahma': 0.95,
    'auntie': 0.9,
  };
  double readsPrice(Sale s) =>
      s.product.fair * reads[s.customer.id]! * (s.customer.loves.contains(kindOf(s.product.id)) ? 1.2 : 1.0);
  String reader(Sale s, int t) => t < 2 ? 'ask:${readsPrice(s)}' : 'take';
  bool loves(Sale s) => s.customer.loves.contains(kindOf(s.product.id));
  // a day: 4 things to sell, customers come one by one, and "Not today" sends one away (3 a day)
  final sellers = <String, (bool Function(Sale), String Function(Sale, int))>{
    'top button, again and again': (
      (_) => true,
      (s, t) => t < 3 ? 'ask:${s.suggestions().isEmpty ? s.offer : s.suggestions().last}' : 'take',
    ),
    'reads the customer, never passes': ((_) => true, reader),
    'waits for a buyer who loves it': (loves, reader),
    'waits for the taitai': ((s) => s.customer.id == 'taitai', reader),
    'waits for the taitai or the chef': ((s) => s.customer.id == 'taitai' || s.customer.id == 'chef', reader),
    'takes the first offer': ((_) => true, (s, t) => 'take'),
  };
  out('\n| seller (3 "Not today" a day) | sold | walked | passed a day | profit a thing sold | ⭐ avg |');
  out('|---|---|---|---|---|---|');
  for (final MapEntry(key: name, value: (keep, play)) in sellers.entries) {
    var tries = 0, sold = 0, walked = 0, passed = 0, stars = 0;
    var profit = 0.0;
    const days = 3000;
    for (var d = 0; d < days; d++) {
      var passes = 3;
      for (var k = 0; k < 4; k++) {
        final p = goods[rnd.nextInt(goods.length)];
        while (true) {
          final s = sale(p, customers[rnd.nextInt(customers.length)], rnd.nextInt(1 << 30));
          if (passes > 0 && !keep(s)) {
            passes--;
            passed++;
            continue;
          }
          tries++;
          for (var t = 0; t < 12 && !s.done; t++) {
            final m = play(s, t);
            m == 'take' ? s.take() : s.askFor(double.parse(m.substring(4)));
          }
          if (s.result == 'sold') {
            sold++;
            stars += s.stars;
            profit += s.profit;
            break;
          }
          walked++; // (it walked: the next customer comes for the same thing)
        }
      }
    }
    String pc(num x) => '${(100 * x / tries).round()}%';
    out(
      '| $name | ${pc(sold)} | ${pc(walked)} | ${(passed / days).toStringAsFixed(1)} | '
      '\$${(profit / sold).toStringAsFixed(2)} | ${(stars / sold).toStringAsFixed(1)} |',
    );
  }
}

void out(String s) => print(s); // ignore: avoid_print
