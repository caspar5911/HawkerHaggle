import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/character.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/main.dart';
import 'package:hawker_haggle/sfx.dart';

const look = {'skin': '#F5D0B5', 'hair': '#4A3B35', 'shirt': '#F28FA3', 'apron': '#FFF2C7', 'accessory': 'perm'};

Map<String, dynamic> game(
  String line, {
  String event = 'greet',
  num ask = 18,
  num? pending,
  String result = '',
  num? deal,
  int stars = 0,
  double saved = 0,
  int qty = 1,
}) {
  final done = result.isNotEmpty;
  return {
    'id': 'g1',
    'stall': 'mei',
    'item': 'mango',
    'event': event,
    'line': line,
    'ai_line': false,
    'you_said': null,
    'ask': ask,
    'opening': 18,
    'patience': 80,
    'mood': 0,
    'qty': qty,
    'done': done,
    'result': result,
    'deal': deal,
    'pending': pending,
    'stars': stars,
    'saved': saved,
    'suggestions': (pending != null || done)
        ? []
        : [
            {'move': 'offer', 'price': 11, 'text': '\$11 can or not?'},
            {'move': 'offer', 'price': 15, 'text': '\$15 lah, OK?'},
            {'move': 'compliment', 'price': null, 'text': 'Wah, looks so good!'},
          ],
    'accept_text': 'OK lah, \$$ask!',
    'walk_text': 'Aiya, never mind lah.',
    'live_left': 999,
  };
}

/// A pretend game: each move gets the next scripted reply; `down` makes loading fail once.
class Fake extends Game {
  Fake(this.replies) : super(content: const {'stalls': [], 'player': {}}, store: MemoryKeyValue());
  final List<Map<String, dynamic>> replies;
  final sent = <Map<String, dynamic>>[];
  int flags = 0;
  bool down = false;

  @override
  Future<void> load() async {}
  @override
  Map<String, Object?> me() {
    if (down) throw GameError(0, "Can't reach the market. Check your internet.");
    return {'name': 'Shiok Otter 123', 'haggles': 0, 'deals': 0, 'stars': 0, 'best_saved': 0};
  }

  @override
  Map<String, Object?> stalls() => {
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
  };
  @override
  Future<Map<String, Object?>> start(String stallId, [String? itemId]) async => game('Morning my dear! \$18 only.');
  @override
  Future<Map<String, Object?>> move(String id, {int? pick, String? move, String? text}) async {
    sent.add({'pick': ?pick, 'move': ?move, 'text': ?text});
    return replies.removeAt(0);
  }

  @override
  Future<void> flag(String id) async => flags++;
}

Api apiFor(Fake f) => Api(game: f, content: const {}, store: MemoryKeyValue());

Future<void> settle(WidgetTester t, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<Fake> openHaggle(WidgetTester tester, List<Map<String, dynamic>> replies) async {
  final fake = Fake(replies);
  await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
  await settle(tester, 2000);
  await tester.tap(find.text('box of mangoes'));
  await settle(tester);
  return fake;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    Sfx.available = false;
  });

  testWidgets('market shows stalls; OK lah turns into Confirm; the second tap buys', (tester) async {
    final fake = await openHaggle(tester, [
      game('OK lah OK lah, \$18!', event: 'accept', result: 'deal', deal: 18, stars: 1),
    ]);
    expect(find.text('Morning my dear! \$18 only.'), findsOneWidget);
    expect(find.text('\$11 can or not?'), findsOneWidget);
    expect(find.textContaining('chats'), findsNothing); // no AI chat limit shown anywhere

    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 600);
    expect(find.text('Confirm \$18'), findsOneWidget); // the button itself asks
    expect(fake.sent, isEmpty); // nothing sent yet
    expect(find.text('Deal! 🎉'), findsNothing);
    await tester.tap(find.text('Confirm \$18'));
    await settle(tester, 2500);
    expect(fake.sent.map((m) => m['move']), ['buy']);
    expect(find.text('Deal! 🎉'), findsOneWidget);
    expect(find.textContaining('Full price'), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('OK lah: backing out with ✕ or waiting sends nothing', (tester) async {
    final fake = await openHaggle(tester, []);
    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 600);
    await tester.tap(find.text('✕'));
    await settle(tester, 600);
    expect(find.text('OK lah, \$18'), findsOneWidget);
    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 6000); // changes back by itself after 5 seconds
    expect(find.text('OK lah, \$18'), findsOneWidget);
    expect(fake.sent, isEmpty);
  });

  testWidgets('when the stallholder agrees to your offer: Deal / Not yet', (tester) async {
    final fake = await openHaggle(tester, [
      game('OK lah, \$15! Deal or not?', event: 'confirm', ask: 17, pending: 15),
      game('OK lah OK lah, \$15!', event: 'accept', result: 'deal', deal: 15, stars: 2, saved: 0.17),
    ]);
    await tester.tap(find.text('\$15 lah, OK?'));
    await settle(tester);
    expect(find.text('Close the deal at \$15?'), findsOneWidget);
    await tester.tap(find.text('Deal, \$15!'));
    await settle(tester, 2500);
    expect(fake.sent.map((m) => m['move'] ?? m['pick']), [1, 'confirm']);
    expect(find.text('Deal! 🎉'), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('the price tag shows the agreed price while waiting, and Not yet goes back to bargaining', (
    tester,
  ) async {
    final fake = await openHaggle(tester, [
      game('OK lah, \$15! Confirm ah?', event: 'confirm', ask: 17, pending: 15),
      game('Take your time, my dear. Still \$15.', event: 'unsure', ask: 15),
    ]);
    await tester.tap(find.text('\$15 lah, OK?'));
    await settle(tester);
    expect(find.text('Close the deal at \$15?'), findsOneWidget);
    expect(find.text('\$15'), findsWidgets); // the tag, not the old $17
    expect(find.text('\$17'), findsNothing);

    await tester.tap(find.text('Not yet'));
    await settle(tester);
    expect(fake.sent.last['move'], 'cancel');
    expect(find.text('Close the deal at \$15?'), findsNothing);
    expect(find.text('\$11 can or not?'), findsOneWidget); // suggestions are back
    expect(find.text('Deal! 🎉'), findsNothing);
    await settle(tester, 3000);
  });

  testWidgets('walking away shows the walked-away card', (tester) async {
    await openHaggle(tester, [game('OK lor, bye bye.', event: 'letgo', result: 'walked')]);
    await tester.tap(find.text('Walk away'));
    await settle(tester, 2500);
    expect(find.text('You walked away 🚶'), findsOneWidget);
    expect(find.textContaining('secret lowest price'), findsOneWidget);
    await settle(tester, 3000);
  });

  testWidgets('running out of patience shows the no-sale card', (tester) async {
    await openHaggle(tester, [game('Auntie no mood already.', event: 'refuse', result: 'refused')]);
    await tester.tap(find.text('Wah, looks so good!'));
    await settle(tester, 2500);
    expect(find.text('No sale today 😅'), findsOneWidget);
    await settle(tester, 3000);
  });

  testWidgets('a two-piece deal says so, with the discount', (tester) async {
    await openHaggle(tester, [
      game('Two ah, \$14 each, confirm?', event: 'confirm', ask: 14, pending: 14, qty: 2),
      game('OK! \$14 each!', event: 'accept', result: 'deal', deal: 14, stars: 2, saved: 0.22, qty: 2),
    ]);
    await tester.tap(find.text('Wah, looks so good!'));
    await settle(tester);
    await tester.tap(find.text('Deal, \$14!'));
    await settle(tester, 2500);
    expect(find.textContaining('each (2 pcs)'), findsOneWidget);
    expect(find.textContaining('22% off'), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('typing opens a box with the last line and sends what you type', (tester) async {
    final fake = await openHaggle(tester, [game('Aiyo your wife so fierce ah? Still \$18.', event: 'smalltalk')]);
    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    expect(find.text('Type your reply…'), findsOneWidget);
    expect(find.text('Morning my dear! \$18 only.'), findsNWidgets(2)); // in the chat and in the box
    await tester.enterText(find.byType(TextField), 'my wife will scold me lah');
    await tester.tap(find.text('Send'));
    await settle(tester, 2500);
    expect(fake.sent.last['text'], 'my wife will scold me lah');
    expect(find.text('my wife will scold me lah', skipOffstage: false), findsOneWidget);
    expect(find.text('Aiyo your wife so fierce ah? Still \$18.', skipOffstage: false), findsOneWidget);
    await settle(tester, 3000);
  });

  testWidgets('cancelling the typing box sends nothing and keeps the draft', (tester) async {
    final fake = await openHaggle(tester, []);
    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    await tester.enterText(find.byType(TextField), 'half a thought');
    await tester.tap(find.text('Cancel'));
    await settle(tester, 600);
    expect(fake.sent, isEmpty);
    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    expect(find.text('half a thought'), findsOneWidget);
    await settle(tester, 2000);
  });

  testWidgets('no internet shows a friendly message and Try again works', (tester) async {
    final fake = Fake([])..down = true;
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.textContaining("Can't reach the market"), findsOneWidget);
    fake.down = false;
    await tester.tap(find.text('Try again'));
    await settle(tester, 2000);
    expect(find.text('Auntie Mei'), findsOneWidget);
  });

  testWidgets('settings: sound switch and the AI endpoint', (tester) async {
    final api = apiFor(Fake([]));
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    expect(Sfx.muted, isFalse);
    await tester.tap(find.byType(Switch));
    await settle(tester, 500);
    expect(Sfx.muted, isTrue);
    await tester.tap(find.byType(Switch));
    await settle(tester, 500);

    await tester.dragUntilVisible(find.text('Save'), find.byType(ListView).last, const Offset(0, -200));
    await tester.enterText(find.byKey(const ValueKey('ai_endpoint')), 'https://example.test/v1/');
    await tester.enterText(find.byKey(const ValueKey('ai_model')), 'test-model');
    await tester.enterText(find.byKey(const ValueKey('ai_key')), 'secret');
    await tester.tap(find.text('Save'));
    await settle(tester, 1500);
    expect(api.ai.endpoint, 'https://example.test/v1/');
    expect(api.ai.model, 'test-model');
    expect(api.ai.apiKey, 'secret');
    expect(api.ai.chatUri.toString(), 'https://example.test/v1/chat/completions');
    await settle(tester, 4000);
  });

  testWidgets('after a typed message you can say she misunderstood; taps cannot be reported', (tester) async {
    final fake = await openHaggle(tester, [
      game('Hehe, nice try. Still \$18.', event: 'smalltalk'),
      game('Left one also \$18 lah!', event: 'smalltalk'),
    ]);
    await tester.tap(find.text('Wah, looks so good!')); // a tap: nothing to report
    await settle(tester);
    expect(find.text('🤔 She misunderstood me', skipOffstage: false), findsNothing);

    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    await tester.enterText(find.byType(TextField), 'I want the one on the left');
    await tester.tap(find.text('Send'));
    await settle(tester, 1500);
    final chip = find.text('🤔 She misunderstood me', skipOffstage: false);
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await settle(tester, 1500);
    expect(fake.flags, 1);
    expect(find.text('✓ Reported, thank you', skipOffstage: false), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('a build with a default AI shows "Use default AI", which fills and saves it', (tester) async {
    final store = MemoryKeyValue();
    await store.write('ai_endpoint', ''); // an empty address was saved earlier
    final api = Api(
      game: Fake([]),
      content: const {},
      store: store,
      builtInEndpoint: 'https://my-model.example/v1',
      builtInModel: 'my-model',
    );
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    expect(api.ai.endpoint, ''); // the saved choice wins over the default...
    await tester.dragUntilVisible(find.text('Use default AI'), find.byType(ListView).last, const Offset(0, -200));
    await tester.tap(find.text('Use default AI'));
    await settle(tester, 1000);
    expect(api.ai.endpoint, 'https://my-model.example/v1'); // ...until you tap the button
    expect(api.ai.model, 'my-model');
    expect(await store.read('ai_endpoint'), 'https://my-model.example/v1');
    expect(find.text('https://my-model.example/v1'), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('the public build has no default, so no button', (tester) async {
    final api = apiFor(Fake([]));
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    expect(find.text('Use default AI', skipOffstage: false), findsNothing);
    await settle(tester, 2000);
  });

  test('faces match the moment', () {
    expect(faceFor('clarify', 0), Face.surprised);
    expect(faceFor('confirm', 0), Face.happy);
    expect(faceFor('plead_no', 0), Face.annoyed);
    expect(faceFor('insulted', 0), Face.angry);
    expect(faceFor('letgo', 0), Face.sad);
    expect(faceFor('pity', 0), Face.sad);
    expect(faceFor('pity_tired', 0), Face.annoyed);
  });
}
