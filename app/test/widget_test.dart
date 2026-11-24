import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/main.dart';
import 'package:hawker_haggle/sfx.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const look = {'skin': '#F5D0B5', 'hair': '#4A3B35', 'shirt': '#F28FA3', 'apron': '#FFF2C7', 'accessory': 'perm'};

Map<String, dynamic> game(String line, {String event = 'greet', bool done = false}) => {
  'id': 'g1',
  'stall': 'mei',
  'item': 'mango',
  'event': event,
  'line': line,
  'ai_line': false,
  'you_said': null,
  'ask': 18,
  'opening': 18,
  'patience': 100,
  'mood': 0,
  'qty': 1,
  'done': done,
  'result': done ? 'deal' : '',
  'deal': done ? 18 : null,
  'stars': done ? 1 : 0,
  'saved': 0.0,
  'suggestions': [
    {'move': 'offer', 'price': 11, 'text': '\$11 can or not?'},
    {'move': 'offer', 'price': 15, 'text': '\$15 lah, OK?'},
    {'move': 'compliment', 'price': null, 'text': 'Wah, looks so good!'},
  ],
  'accept_text': 'OK lah, \$18!',
  'walk_text': 'Aiya, never mind lah.',
  'live_left': 15,
};

final sent = <String>[];

MockClient fakeServer() => MockClient((req) async {
  final p = req.url.path;
  if (req.body.isNotEmpty) sent.add(req.body);
  final Object body = switch (p) {
    '/v1/device' => {
      'token': 't',
      'player': {'name': 'Shiok Otter 123'},
    },
    '/v1/me' => {'name': 'Shiok Otter 123', 'haggles': 0, 'deals': 0, 'stars': 0, 'best_saved': 0, 'live_left': 15},
    '/v1/stalls' => {
      'stalls': [
        {
          'id': 'mei',
          'name': 'Auntie Mei',
          'stall': 'Fruit stall',
          'place': 'Wet market',
          'look': look,
          'items': [
            {'id': 'mango', 'name': 'box of mangoes', 'emoji': '🥭', 'ask': 18, 'stars': 2},
          ],
        },
      ],
    },
    '/v1/haggle' => game('Morning my dear! \$18 only.'),
    '/v1/haggle/g1/move' => game('OK lah OK lah, \$18!', event: 'accept', done: true),
    _ => {'detail': 'nope'},
  };
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
});

Future<void> settle(WidgetTester t, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    Sfx.available = false;
  });

  testWidgets('market shows stalls and a haggle reaches a deal', (tester) async {
    final api = Api(client: fakeServer(), base: 'http://test');
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    expect(find.text('Hawker Haggle'), findsOneWidget);
    expect(find.text('Auntie Mei'), findsOneWidget);
    expect(find.textContaining('Shiok Otter 123'), findsOneWidget);

    await tester.tap(find.text('box of mangoes'));
    await settle(tester);
    expect(find.text('Morning my dear! \$18 only.'), findsOneWidget);
    expect(find.text('\$11 can or not?'), findsOneWidget);

    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 2500);
    expect(find.text('Deal! 🎉'), findsOneWidget);
    await settle(tester, 4000); // let confetti and timers finish
  });

  testWidgets('typing opens a box with the last line, and sends what you type', (tester) async {
    sent.clear();
    final api = Api(client: fakeServer(), base: 'http://test');
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.text('box of mangoes'));
    await settle(tester);

    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    expect(find.text('Type your reply…'), findsOneWidget);
    expect(find.text('Morning my dear! \$18 only.'), findsNWidgets(2)); // in the chat and in the box
    await tester.enterText(find.byType(TextField), 'my wife will scold me lah');
    await tester.tap(find.text('Send'));
    await settle(tester, 2500);
    expect(sent.last, contains('my wife will scold me lah'));
    expect(find.text('my wife will scold me lah'), findsOneWidget); // shown in the chat
    await settle(tester, 4000);
  });
}
