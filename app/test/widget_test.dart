import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/juice.dart';
import 'package:hawker_haggle/character.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/extras.dart';
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
  Map<String, dynamic>? first; // the greeting (default: Auntie Mei's)
  final sent = <Map<String, dynamic>>[];
  int flags = 0;
  bool down = false;
  String name = 'Shiok Otter 123';
  bool named = true; // false: a first launch, which asks for a name
  Map<String, Object?>? festival;

  @override
  Future<void> load() async {}
  @override
  Map<String, Object?> me() {
    if (down) throw GameError(0, "Can't reach the market. Check your internet.");
    return {'name': name, 'named': named, 'haggles': 0, 'deals': 0, 'stars': 0, 'best_saved': 0, 'festival': festival};
  }

  @override
  Future<String> setName(String raw) async {
    final n = cleanName(raw);
    if (n == null) throw GameError(400, 'Pick a name with some letters in it.');
    name = n;
    named = true;
    return n;
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
  Future<Map<String, Object?>> start(String stallId, [String? itemId, String? surprise]) async {
    lastSurprise = surprise;
    return first ?? game('Morning my dear! \$18 only.');
  }

  @override
  Future<Map<String, Object?>> move(String id, {int? pick, String? move, String? text}) async {
    sent.add({'pick': ?pick, 'move': ?move, 'text': ?text});
    return replies.removeAt(0);
  }

  @override
  Future<void> flag(String id) async => flags++;

  num? guessed;
  @override
  Future<void> guess(String id, num price) async => guessed = price;

  @override
  Map<String, Object?> today() => {
    'items': [
      {'stall': 'mei', 'item': 'mango', 'name': 'mangoes for Mum', 'emoji': '🥭', 'done': false, 'paid': null},
      {'stall': 'lim', 'item': 'pomfret', 'name': 'pomfret', 'emoji': '🐟', 'done': true, 'paid': 15},
    ],
    'budget': 30,
    'spent': 15,
    'complete': false,
    'under': false,
    'streak': 2,
    'tip': 'Auntie Mei loves compliments.',
  };

  @override
  Map<String, Object?> challenges() => {
    'rank': {'level': 3, 'title': 'Bargain Spotter', 'xp': 300, 'from': 250, 'next': 450, 'max': false},
    'daily': {
      'id': 'rain_deal',
      'title': 'Rainy-day bargain',
      'how': 'Close a deal on a rainy day.',
      'done': false,
      'surprise': 'rain',
      'stall': 'mei',
    },
    'quests': [
      {'id': 'deals', 'title': 'Close 6 deals', 'target': 6, 'have': 2, 'done': false},
      {'id': 'list', 'title': "Finish Mum's list on 3 days", 'target': 3, 'have': 3, 'done': true},
    ],
    'week_ends': '2026-11-29',
    'days_played': 5,
    'month': [
      {'day': 3, 'emoji': '🌱', 'what': 'Sticker: Three market days', 'reached': true},
      {'day': 7, 'emoji': '🏺', 'what': "Uncle Wong's antique stall opens", 'reached': false},
    ],
  };

  String? lastSurprise;

  @override
  List<Map<String, Object?>> history() => [
    {
      'id': 'h1',
      'at': '2026-11-24T20:30:00',
      'stall': 'mei',
      'item': 'mango',
      'result': 'deal',
      'deal': 15,
      'stars': 2,
      'saved': 0.17,
      'qty': 1,
      'stall_name': 'Auntie Mei',
      'item_name': 'box of mangoes',
      'emoji': '🥭',
    },
  ];

  @override
  Map<String, Object?> historyItem(String id) => {
    ...history().first,
    'chat': [
      {'who': 'them', 'text': 'Morning my dear! \$18 only.'},
      for (var i = 0; i < extraChat; i++) ...[
        {'who': 'you', 'text': 'Chat line $i?'},
        {'who': 'them', 'text': 'Answer $i!'},
      ],
      {'who': 'you', 'text': '\$15 lah, OK?'},
      {'who': 'them', 'text': 'OK lah, \$15 for you!', 'ai': true},
    ],
  };
  int extraChat = 0; // a longer chat, for sharing in parts

  @override
  List<Map<String, Object?>> stickers() => [
    {'id': 'first_deal', 'emoji': '🤝', 'title': 'First deal', 'how': 'Close your first deal', 'earned': '2026-11-24'},
    {'id': 'half_off', 'emoji': '✂️', 'title': 'Half price!', 'how': 'Get half off', 'earned': null},
  ];
}

Api apiFor(Fake f) => Api(game: f, content: const {}, store: MemoryKeyValue());

Future<void> settle(WidgetTester t, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<Fake> openHaggle(WidgetTester tester, List<Map<String, dynamic>> replies, {Fake? fake}) async {
  fake ??= Fake(replies);
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

  testWidgets('first launch asks for a name (random one ready); the 👋 chip and Settings change it', (tester) async {
    final fake = Fake([])..named = false;
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.text('👋 Welcome to the market!'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing); // must pick (or keep) one
    await tester.tap(find.byKey(const ValueKey('name_dice')));
    await settle(tester, 300);
    final rolled = tester.widget<TextField>(find.byKey(const ValueKey('name_field'))).controller!.text;
    expect(rolled, isNot('Shiok Otter 123'));
    await tester.enterText(find.byKey(const ValueKey('name_field')), '  123 ');
    await tester.tap(find.byKey(const ValueKey('name_save')));
    await settle(tester, 500);
    expect(find.text('Pick a name with some letters in it.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('name_field')), 'Caspar <b>');
    await tester.tap(find.byKey(const ValueKey('name_save')));
    await settle(tester, 800);
    expect(find.text('👋 Welcome to the market!'), findsNothing);
    expect(fake.name, 'Caspar b');
    expect(find.text('👋 Caspar b ✏️'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('name_chip')));
    await settle(tester, 500);
    await tester.enterText(find.byKey(const ValueKey('name_field')), 'Ah Boy');
    await tester.tap(find.byKey(const ValueKey('name_save')));
    await settle(tester, 800);
    expect(find.text('👋 Ah Boy ✏️'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    expect(find.text('Ah Boy'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_name')));
    await settle(tester, 500);
    await tester.tap(find.text('Cancel'));
    await settle(tester, 500);
    expect(fake.name, 'Ah Boy');
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
    await tester.tap(find.byKey(const ValueKey('walk')));
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
    expect(find.textContaining("That's 22% off"), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('typing opens a box with the last line and sends what you type', (tester) async {
    final fake = await openHaggle(tester, [game('Aiyo your wife so fierce ah? Still \$18.', event: 'smalltalk')]);
    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    expect(find.text('Type your reply…'), findsOneWidget);
    expect(find.text('Morning my dear! \$18 only.'), findsNWidgets(2)); // in the chat and in the box
    await tester.enterText(find.byKey(const ValueKey('reply_field')), 'my wife will scold me lah');
    await tester.tap(find.text('Send'));
    await settle(tester, 2500);
    expect(fake.sent.last['text'], 'my wife will scold me lah');
    expect(find.text('my wife will scold me lah', skipOffstage: false), findsOneWidget);
    expect(find.text('Aiyo your wife so fierce ah? Still \$18.', skipOffstage: false), findsOneWidget);
    await settle(tester, 3000);
  });

  testWidgets('holding a suggestion puts it in the typing box to edit before sending', (tester) async {
    final fake = await openHaggle(tester, [game('Every week ah? OK lah, \$15!', event: 'counter', ask: 15)]);
    await tester.longPress(find.text('\$15 lah, OK?'));
    await settle(tester, 600);
    expect(find.text('Type your reply…'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('reply_field')));
    expect(field.controller!.text, '\$15 lah, OK?');
    expect(fake.sent, isEmpty); // nothing sent by holding
    await tester.enterText(find.byKey(const ValueKey('reply_field')), '\$15 lah, OK? I come every week one!');
    await tester.tap(find.text('Send'));
    await settle(tester, 2000);
    expect(fake.sent.last['text'], '\$15 lah, OK? I come every week one!');
    await settle(tester, 3000);
  });

  testWidgets('cancelling the typing box sends nothing and keeps the draft', (tester) async {
    final fake = await openHaggle(tester, []);
    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('reply_field')), 'half a thought');
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
    await tester.tap(find.byType(Switch).first);
    await settle(tester, 500);
    expect(Sfx.muted, isTrue);
    await tester.tap(find.byType(Switch).first);
    await settle(tester, 500);

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('ai_endpoint')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('ai_endpoint')));
    await settle(tester, 300);
    await tester.enterText(find.byKey(const ValueKey('ai_endpoint')), 'https://example.test/v1/');
    await tester.enterText(find.byKey(const ValueKey('ai_model')), 'test-model');
    await tester.enterText(find.byKey(const ValueKey('ai_key')), 'secret');
    FocusManager.instance.primaryFocus?.unfocus(); // the keyboard goes; the list stops moving
    await settle(tester, 500);
    await tester.ensureVisible(find.text('Save'));
    await settle(tester, 300);
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
    await tester.enterText(find.byKey(const ValueKey('reply_field')), 'I want the one on the left');
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
    expect(api.ai.endpoint, 'https://my-model.example/v1'); // an empty saved address falls back to the default
    await store.write('ai_endpoint', 'https://other.example/v1');
    await api.setAi(endpoint: 'https://other.example/v1', model: 'other', apiKey: '');
    expect(api.ai.endpoint, 'https://other.example/v1'); // another saved address wins...
    await tester.dragUntilVisible(find.text('Use default AI'), find.byType(ListView).last, const Offset(0, -200));
    await tester.ensureVisible(find.text('Use default AI'));
    await settle(tester, 300);
    await tester.tap(find.text('Use default AI'));
    await settle(tester, 1000);
    expect(api.ai.endpoint, 'https://my-model.example/v1'); // ...until you tap the button
    expect(api.ai.model, 'my-model');
    expect(await store.read('ai_endpoint'), 'https://my-model.example/v1');
    expect(find.text('https://my-model.example/v1'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('build_label')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    expect(find.textContaining('your build, AI built in'), findsOneWidget);
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

  testWidgets("market shows Mum's list, streak and stickers; the list opens a haggle; the sticker book opens", (
    tester,
  ) async {
    final fake = Fake([]);
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.text("Mum's list today"), findsOneWidget);
    expect(find.text('🔥 2'), findsOneWidget);
    expect(find.textContaining("Mum's tip"), findsOneWidget);
    await tester.tap(find.text('mangoes for Mum'));
    await settle(tester);
    expect(find.text('Morning my dear! \$18 only.'), findsOneWidget); // the haggle opened
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('sticker_book')));
    await settle(tester);
    expect(find.text('1 of 2 collected'), findsOneWidget);
    expect(find.text('Half price!'), findsOneWidget);
    await settle(tester, 2000);
  });

  testWidgets('the rival auntie: banner during the haggle, and the lost card', (tester) async {
    final rival = game('Last one ah! \$18.')
      ..addAll({'surprise': 'rival', 'surprise_note': '👵 Auntie Rose wants the last one too: 4 moves left!'});
    final fake = Fake([
      game('Sorry, sold to Auntie Rose!', event: 'rival_bought', result: 'lost')..addAll({
        'surprise': 'rival',
        'new_stickers': ['half_off'],
      }),
    ]);
    fake.first = rival;
    await openHaggle(tester, fake.replies, fake: fake);
    expect(find.textContaining('Auntie Rose wants the last one'), findsOneWidget);
    await tester.tap(find.text('Wah, looks so good!'));
    await settle(tester, 2500);
    expect(find.text('Auntie Rose got it! 😱'), findsOneWidget);
    expect(find.textContaining('New sticker!'), findsOneWidget);
    await settle(tester, 3000);
  });

  testWidgets('a great deal can be shared as a picture', (tester) async {
    final shared = <String>[];
    shareBrag = (text, png) async => shared.add(text);
    capturePng = (_) async => null;
    final fake = await openHaggle(tester, [
      game('OK lah OK lah, \$12!', event: 'accept', result: 'deal', deal: 12, stars: 3, saved: 0.33)
        ..addAll({'mum': 'Mum: Wah, so clever! \$12, under budget.'}),
    ]);
    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 600);
    await tester.tap(find.text('Confirm \$18'));
    await settle(tester, 2500);
    expect(fake.sent.last['move'], 'buy');
    expect(find.textContaining('Mum: Wah, so clever!'), findsOneWidget);
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await settle(tester, 1000);
    expect(shared.single, contains('33% off'));
    await settle(tester, 3000);
  });

  testWidgets('past haggles: the list, and a chat to reread', (tester) async {
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('history')));
    await settle(tester);
    expect(find.text('box of mangoes · Auntie Mei'), findsOneWidget);
    expect(find.textContaining('Bought for \$15'), findsOneWidget);
    await tester.tap(find.text('box of mangoes · Auntie Mei'));
    await settle(tester);
    expect(find.text('\$15 lah, OK?'), findsOneWidget);
    expect(find.textContaining('OK lah, \$15 for you!'), findsOneWidget);
    expect(find.text('Bought for \$15'), findsOneWidget);
    await settle(tester, 2000);
  });

  testWidgets('guess the fair price before the first move; Skip hides it; a move hides it too', (tester) async {
    final fake = await openHaggle(tester, [game('Every week ah? OK lah, \$15!', event: 'counter', ask: 15)]);
    expect(find.byKey(const ValueKey('guess_card')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('guess_field')), '13');
    await tester.tap(find.byKey(const ValueKey('guess_go')));
    await settle(tester, 600);
    expect(fake.guessed, 13);
    expect(find.text("🤔 Your guess: \$13. Let's see when the haggle ends!"), findsOneWidget);
    await tester.tap(find.text('\$11 can or not?'));
    await settle(tester, 2000);
    expect(find.byKey(const ValueKey('guess_card')), findsNothing);
    await settle(tester, 3000);
  });

  testWidgets('your own stall: a customer offers, you sell, then the next customer', (tester) async {
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('shop_open')));
    await settle(tester, 1500);
    expect(find.textContaining('wants your'), findsOneWidget);
    expect(find.textContaining('you paid'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shop_take')));
    await settle(tester, 1500);
    expect(find.textContaining('Sold for'), findsOneWidget);
    expect(find.textContaining('sold ·'), findsOneWidget); // the running total
    await tester.tap(find.byKey(const ValueKey('shop_next')));
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('shop_result')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('shop_price')), '500');
    await tester.tap(find.byKey(const ValueKey('shop_ask')));
    await settle(tester, 1500);
    expect(find.text('\$500, can?'), findsOneWidget);
    await settle(tester, 2000);
  });

  testWidgets('a soft spot toast, a "convince me" banner, and how close you got on the result', (tester) async {
    final fake = await openHaggle(tester, [
      game('Fishing ah? Wah, I love it! \$16 for you.', event: 'counter', ask: 16)
        ..addAll({'found': 'fishing trips', 'challenge': true}),
      game('Wah, okay okay, you convinced me! \$12!', event: 'accept', result: 'deal', deal: 12, stars: 3, saved: 0.33)
        ..addAll({'pitch_score': 2, 'closeness': "🎯 Right at Auntie Mei's limit!"}),
    ]);
    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('reply_field')), 'auntie you go fishing?');
    await tester.tap(find.text('Send'));
    await settle(tester, 800);
    expect(find.textContaining("You found Auntie Mei's soft spot: fishing trips!"), findsOneWidget);
    expect(find.text('💬 Auntie Mei wants convincing! Type your best pitch.'), findsOneWidget);
    await settle(tester, 4000); // the toast goes
    await tester.tap(find.textContaining('Say anything'));
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('reply_field')), 'my grandma loves your mangoes!');
    await tester.tap(find.text('Send'));
    await settle(tester, 2500);
    expect(fake.sent.last['text'], 'my grandma loves your mangoes!');
    expect(find.textContaining('What a pitch!'), findsOneWidget);
    expect(find.textContaining("Right at Auntie Mei's limit!"), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('juice: the DEAL! stamp before the result; Reduce motion in Settings', (tester) async {
    await openHaggle(tester, [game('OK lah OK lah, \$18!', event: 'accept', result: 'deal', deal: 18, stars: 1)]);
    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 600);
    await tester.tap(find.text('Confirm \$18'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('deal_stamp')), findsOneWidget);
    await settle(tester, 2500);
    expect(find.byKey(const ValueKey('deal_stamp')), findsNothing); // the result card takes over
    await settle(tester, 2000);
  });

  testWidgets('Reduce motion can be switched on in Settings', (tester) async {
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    expect(Motion.reduced, isFalse);
    await tester.tap(find.byKey(const ValueKey('reduce_motion')));
    await settle(tester, 400);
    expect(Motion.reduced, isTrue);
    await tester.tap(find.byKey(const ValueKey('reduce_motion')));
    await settle(tester, 400);
    expect(Motion.reduced, isFalse);
  });

  testWidgets('a festival week shows on the market', (tester) async {
    final fake = Fake([])..festival = {'id': 'cny2027', 'name': 'Chinese New Year', 'emoji': '🧧', 'to': '2027-02-08'};
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.textContaining('🧧 Chinese New Year week at the market!'), findsOneWidget);
    await settle(tester, 2000);
  });

  testWidgets('skipping the guess', (tester) async {
    final fake = await openHaggle(tester, [game('Hmm, \$16.', event: 'counter', ask: 16)]);
    await tester.tap(find.byKey(const ValueKey('guess_skip')));
    await settle(tester, 400);
    expect(find.byKey(const ValueKey('guess_card')), findsNothing);
    expect(fake.guessed, isNull);
    await settle(tester, 3000);
  });

  testWidgets('a past chat: pick lines and share them as a picture', (tester) async {
    final shared = <String>[];
    shareBrag = (text, png) async => shared.add(text);
    capturePng = (_) async => null;
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('history')));
    await settle(tester);
    await tester.tap(find.text('box of mangoes · Auntie Mei'));
    await settle(tester);
    expect(find.textContaining('Share as a picture ('), findsOneWidget);
    // the whole chat is picked to start with; None, then All, picks everything again
    await tester.tap(find.byKey(const ValueKey('pick_none')));
    await settle(tester, 300);
    expect(find.text('Share as a picture (0)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick_all')));
    await settle(tester, 300);
    await tester.ensureVisible(find.byKey(const ValueKey('chat_share')));
    await tester.tap(find.byKey(const ValueKey('chat_share')));
    await settle(tester, 800);
    await tester.tap(find.byKey(const ValueKey('chat_share_go')));
    await settle(tester, 800);
    expect(shared.single, contains('Auntie Mei · box of mangoes'));
    expect(shared.single, contains('\$15 lah, OK?')); // the first line…
    expect(shared.single, contains('OK lah, \$15 for you!')); // …and the last
    expect(shared.single, contains('🏮 Hawker Haggle'));
    await settle(tester, 2000);
  });

  testWidgets('a long chat can be shared as one tall picture or as numbered pictures', (tester) async {
    final shared = <String>[];
    var pictures = 0;
    shareBrag = (text, png) async => shared.add('one');
    sharePictures = (text, pngs) async {
      shared.add('parts');
      pictures = pngs.length;
    };
    capturePng = (_) async => Uint8List(4);
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([])..extraChat = 9))); // 21 messages
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('history')));
    await settle(tester);
    await tester.tap(find.text('box of mangoes · Auntie Mei'));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('chat_share')),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await settle(tester, 300);
    expect(find.text('Share as a picture (21)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat_share')));
    await settle(tester, 800);
    expect(find.text('3 pictures'), findsOneWidget); // 8 + 8 + 5
    expect(find.text('1/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat_share_go')));
    await settle(tester, 800);
    expect(shared.last, 'parts');
    expect(pictures, 3);
    // or one tall picture
    await tester.tap(find.byKey(const ValueKey('chat_share')));
    await settle(tester, 800);
    await tester.tap(find.text('One picture'));
    await settle(tester, 500);
    expect(find.text('1/3'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat_share_go')));
    await settle(tester, 800);
    expect(shared.last, 'one');
    await settle(tester, 2000);
  });

  testWidgets('challenges: the strip on the market, the screen, and Play starts the right surprise', (tester) async {
    final fake = Fake([]);
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.text('Today: Rainy-day bargain'), findsOneWidget);
    expect(find.text('Lv 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('challenge_strip')));
    await settle(tester);
    expect(find.text('Level 3 · Bargain Spotter'), findsOneWidget);
    expect(find.text("Today's challenge: Rainy-day bargain"), findsOneWidget);
    expect(find.text('Close 6 deals'), findsOneWidget);
    await tester.dragUntilVisible(
      find.textContaining('Market Month'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    expect(find.textContaining('day 5 of 30'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('daily_play')),
      find.byType(ListView).last,
      const Offset(0, 200),
    );
    await tester.tap(find.byKey(const ValueKey('daily_play')));
    await settle(tester, 2000);
    expect(fake.lastSurprise, 'rain');
    expect(find.text('Morning my dear! \$18 only.'), findsOneWidget);
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
