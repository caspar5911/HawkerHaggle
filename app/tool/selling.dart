// How hard is selling at your own stall? Plays many sales (no AI: the customer rules only) with different sellers,
// and prints how often each sells, the price against the usual one, and the stars.
// Run: dart run tool/selling.dart
import 'dart:math' as math;

import 'package:hawker_haggle/core/shop.dart';

typedef Seller = String Function(Sale s, int turn);

void main() {
  const product = Product('mango', 'box of mangoes', '🥭', 13, 18); // bought for $13, usually $18 at your stall
  // what a careful seller makes of each customer's clue (never their real limit)
  const reads = {'taitai': 1.35, 'tourist': 1.2, 'uncle': 0.95, 'student': 0.8};
  final sellers = <String, Seller>{
    // presses the top price button again and again, then takes the offer
    'top button, again and again': (s, t) =>
        t < 3 ? 'ask:${s.suggestions().isEmpty ? s.offer : s.suggestions().last}' : 'take',
    // the usual price, held firm, then takes the offer
    'the usual price, held': (s, t) => t < 2 ? 'ask:${product.fair}' : 'take',
    // reads the clue: a price for that kind of customer, held once; if it was too much, takes the offer
    'reads the clue, holds once': (s, t) => t < 2 ? 'ask:${product.fair * reads[s.customer.id]!}' : 'take',
    // asks 1.5x the usual price straight away
    'very greedy (1.5x)': (s, t) => t < 2 ? 'ask:${product.fair * 1.5}' : 'take',
    // takes the first offer
    'takes the first offer': (s, t) => 'take',
  };
  final rnd = math.Random(1);
  out('| seller | sold | they walked | price / usual | profit | ⭐ avg | ⭐⭐⭐ |');
  out('|---|---|---|---|---|---|---|');
  for (final MapEntry(key: name, value: play) in sellers.entries) {
    var n = 0, sold = 0, walked = 0, stars = 0, three = 0;
    var ratio = 0.0, profit = 0.0;
    for (var i = 0; i < 4000; i++) {
      final s = Sale(product, customers[rnd.nextInt(customers.length)], seed: rnd.nextInt(1 << 30));
      n++;
      for (var t = 0; t < 12 && !s.done; t++) {
        final move = play(s, t);
        if (move == 'take') {
          s.take();
        } else {
          s.askFor(double.parse(move.substring(4)));
        }
      }
      if (s.result == 'sold') {
        sold++;
        stars += s.stars;
        if (s.stars == 3) three++;
        ratio += s.price! / product.fair;
        profit += s.profit;
      } else {
        walked++;
      }
    }
    String pc(num x) => '${(100 * x / n).round()}%';
    out(
      '| $name | ${pc(sold)} | ${pc(walked)} | ${sold == 0 ? '-' : (ratio / sold).toStringAsFixed(2)} | '
      '\$${(profit / n).toStringAsFixed(2)} a customer | ${sold == 0 ? '-' : (stars / sold).toStringAsFixed(1)} | '
      '${pc(three)} |',
    );
  }
}

void out(String s) => print(s); // ignore: avoid_print
