// Run your own stall: every customer with every product and every way of selling ends; the maths is right; the AI
// never gets to say a price the code didn't give.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/ai_client.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/core/shop.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

const styles = ['bold', 'fair', 'take', 'chatty', 'greedy', 'step_down', 'random'];

/// Play one sale to the end with a selling style. Returns the number of moves.
int play(Sale s, String style, math.Random rnd) {
  var moves = 0;
  var askAt = s.product.fair * 1.6;
  while (!s.done && moves < 30) {
    moves++;
    switch (style) {
      case 'bold':
        s.askFor(s.product.fair * 1.3);
      case 'fair':
        s.askFor(s.product.fair);
      case 'take':
        s.take();
      case 'chatty':
        moves.isOdd ? s.chat() : s.askFor(s.product.fair * 1.2);
      case 'greedy':
        s.askFor(s.product.fair * 5);
      case 'step_down':
        s.askFor(askAt);
        askAt = math.max(s.product.cost, askAt - 1.5);
      default:
        switch (rnd.nextInt(3)) {
          case 0:
            s.askFor(s.offer + rnd.nextInt(20));
          case 1:
            s.chat();
          default:
            if (rnd.nextInt(4) == 0) s.take();
        }
    }
  }
  return moves;
}

void main() {
  test('every customer, product and selling style ends, with the right result and maths', () {
    final rnd = math.Random(7);
    final results = <String, int>{};
    for (final c in customers) {
      for (final p in products) {
        for (final style in styles) {
          for (var i = 0; i < 25; i++) {
            final s = Sale(p, c, seed: rnd.nextInt(1 << 31));
            expect(s.offer, lessThanOrEqualTo(s.most));
            final moves = play(s, style, rnd);
            expect(s.done, isTrue, reason: '${c.id}/${p.id}/$style never ended');
            expect(moves, lessThanOrEqualTo(12));
            results['$style/${s.result}'] = (results['$style/${s.result}'] ?? 0) + 1;
            if (s.result == 'sold') {
              expect(s.price, isNotNull);
              expect(s.price! <= s.most || s.price == s.offer, isTrue); // never more than they'd pay
              expect(s.profit, closeTo(s.price! - p.cost, 1e-9));
              expect(s.price! * 2, (s.price! * 2).roundToDouble()); // 50-cent steps
            } else {
              expect(s.price, isNull);
              expect(s.profit, 0);
            }
          }
        }
      }
    }
    expect(results['take/sold'], customers.length * products.length * 25); // taking the offer always sells
    expect(results['greedy/walked'], customers.length * products.length * 25); // asking 5x never sells
    expect(results['fair/sold'], greaterThan(0));
    expect(results['bold/walked'], greaterThan(0)); // the uncle and the student won't pay 30% over
    expect(results['bold/sold'], greaterThan(0)); // the tourist and Mrs Chua will
  });

  test('stars: 3 well above the usual price, 2 at it, 1 for any profit, 0 for a loss', () {
    final p = products.first; // cost 8, usual 12
    Sale sold(double x) {
      final s = Sale(p, customers.firstWhere((c) => c.id == 'taitai'), seed: 1);
      s.most = 100;
      s.askFor(x);
      return s;
    }

    expect(sold(15).stars, 3);
    expect(sold(12).stars, 2);
    expect(sold(9).stars, 1);
    expect(sold(7).stars, 0);
    expect(sold(9).profit, 1);
  });

  test('their offer only goes up, never past the most they pay; asking too much costs patience', () {
    for (var seed = 0; seed < 50; seed++) {
      final s = Sale(products[1], customers.first, seed: seed);
      var last = s.offer;
      while (!s.done) {
        final e = s.askFor(s.most + 2);
        if (e == 'raise') {
          expect(s.offer, greaterThanOrEqualTo(last));
          expect(s.offer, lessThanOrEqualTo(s.most));
        }
        last = s.offer;
      }
      expect(s.result, 'walked');
    }
  });

  test('through the game: a sale ends, counts, and earns the shopkeeper sticker', () async {
    final g = Game(content: content, store: MemoryKeyValue(), random: math.Random(3));
    await g.load();
    var sold = 0;
    for (var i = 0; i < 12; i++) {
      var r = await g.shopStart();
      expect('${r['line']}', isNotEmpty);
      expect(r['suggestions'] as List, isNotEmpty);
      final id = r['id'] as String;
      final fair = ((r['product'] as Map)['fair'] as num).toDouble();
      r = await g.shopMove(id, ask: fair);
      if (r['done'] != true) r = await g.shopMove(id, take: true);
      expect(r['done'], isTrue);
      if (r['result'] == 'sold') sold++;
      await expectLater(g.shopMove(id, take: true), throwsA(isA<GameError>()));
    }
    expect(sold, 12);
    expect(g.stickers().firstWhere((s) => s['id'] == 'shopkeeper')['earned'], isNotNull);
    expect(g.me()['haggles'], 0); // selling isn't haggling: challenges and the month's pacing are untouched
  });

  test("the AI writes the customer's words, but a price the code didn't give is thrown out", () async {
    var calls = 0;
    var reply = r'Boss, $3 can or not?'; // a price the code never gave
    final ai = AiClient(
      const AiConfig(endpoint: 'https://ai.example/v1', model: 'm'),
      client: MockClient((req) async {
        calls++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': reply},
              },
            ],
          }),
          200,
        );
      }),
    );
    final s = Sale(products.first, customers.first, seed: 5);
    expect(await customerSay(ai, s, 'greet', const []), isNull); // rejected twice: the ready-made line is used
    expect(calls, 2);
    reply = 'Boss, ${money2(s.offer)} can or not?';
    expect(await customerSay(ai, s, 'greet', const []), reply);
    expect(customerLine(s, 'greet', 1), contains(money2(s.offer)));
  });
}
