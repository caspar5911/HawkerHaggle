import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/juice.dart';
import 'package:hawker_haggle/challenge_link.dart';
import 'package:hawker_haggle/character.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/extras.dart';
import 'package:hawker_haggle/guide.dart';
import 'package:hawker_haggle/main.dart';
import 'package:hawker_haggle/screens.dart' show startAddress;
import 'package:hawker_haggle/music.dart';
import 'package:hawker_haggle/reminder.dart';
import 'package:hawker_haggle/sfx.dart';
import 'package:hawker_haggle/voice.dart';

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
  bool named = true;
  int haggles = 1;
  num? wallet; // 👛 (null: no wallet shown)
  bool short = false; // the mangoes cost more than the wallet
  Map<String, Object?>? festival;

  @override
  Future<void> load() async {}
  @override
  Map<String, Object?> me() {
    if (down) throw GameError(0, "Can't reach the market. Check your internet.");
    return {
      'name': name,
      'named': named,
      'haggles': haggles,
      'deals': 0,
      'stars': 0,
      'best_saved': 0,
      'festival': festival,
      if (wallet != null) ...{'wallet': wallet, 'pocket': 20},
    };
  }

  @override
  Future<String> setName(String raw) async {
    final n = cleanName(raw);
    if (n == null) throw GameError(400, 'Pick a name with some letters in it.');
    name = n;
    named = true;
    return n;
  }

  Map<String, Object?>? legend; // today's legendary item (a test sets it)
  Map<String, Object?>? nextLegend; // the next one, on other days (a test sets it)

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
          {'id': 'mango', 'name': 'box of mangoes', 'emoji': '🥭', 'ask': 18, 'stars': 2, if (short) 'short': true},
          ?legend,
        ],
      },
    ],
    'legendary': legend == null ? null : {...legend!, 'stall': 'mei', 'stall_name': 'Auntie Mei'},
    'next_legendary': nextLegend,
  };
  @override
  Future<Map<String, Object?>> start(String stallId, [String? itemId, String? surprise, bool anyStall = false]) async {
    lastSurprise = surprise;
    lastAnyStall = anyStall;
    return first ?? game('Morning my dear! \$18 only.');
  }

  @override
  Future<Map<String, Object?>> move(String id, {int? pick, String? move, String? text, String? friend}) async {
    sent.add({'pick': ?pick, 'move': ?move, 'text': ?text, 'friend': ?friend});
    return replies.removeAt(0);
  }

  @override
  Future<void> flag(String id) async => flags++;

  num? guessed;
  @override
  Future<void> guess(String id, num price) async => guessed = price;

  final answered = <String>[];
  @override
  Future<String> answerTwist(String id, int choice) async {
    answered.add('twist $choice');
    return 'Auntie Mei cheers you on: "Catch it!"';
  }

  @override
  Future<String> answerDilemma(String id, {required bool help}) async {
    answered.add('dilemma $help');
    return help ? '💛 Auntie Mei is touched' : '';
  }

  final saved = <String>[];
  @override
  Future<bool> saveQuote(String stallId, String text) async {
    saved.add(text);
    return true;
  }

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
  bool lastAnyStall = false;

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
  fake ??= Fake(replies)..haggles = MumGuide.enabled ? 0 : 1;
  await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
  await settle(tester, 2000);
  if (fake.haggles == 0) {
    await tester.tap(find.byKey(const ValueKey('browse_market')));
    await settle(tester);
  }
  await tester.ensureVisible(find.text('box of mangoes'));
  await settle(tester, 300);
  await tester.tap(find.text('box of mangoes'));
  await settle(tester);
  return fake;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    Sfx.available = false;
    Music.reset();
    MumGuide.enabled = false; // a new test player has never haggled: Mum's tips only in their own tests
    Reminder.instance = _Reminder();
    Voice.useKeyboard = false;
  });

  testWidgets('market shows stalls; OK lah turns into Confirm; the second tap buys', (tester) async {
    final fake = await openHaggle(tester, [
      game('OK lah OK lah, \$18!', event: 'accept', result: 'deal', deal: 18, stars: 1),
    ]);
    expect(find.text('Morning my dear! \$18 only.'), findsOneWidget);
    expect(find.text('\$11 can or not?'), findsOneWidget);
    expect(Music.wanted, 'calm'); // the softer tune under a haggle
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

  testWidgets('👛 the wallet on screen: the chip, Mum\'s pocket money, "more than you have", and in a haggle', (
    tester,
  ) async {
    final fake = Fake([])
      ..wallet = 12.5
      ..short = true
      ..first = {...game('Morning my dear! \$18 only.'), 'wallet': 12.5, 'mum_pays': false};
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.text('👛 \$12.50'), findsOneWidget);
    expect(find.textContaining('Mum gave you \$20 pocket money'), findsOneWidget);
    expect(find.textContaining('more than you have'), findsOneWidget);
    await tester.tap(find.textContaining('box of mangoes').last);
    await settle(tester, 2000);
    expect(find.textContaining('👛 \$12.50'), findsOneWidget); // under the stallholder's name
    expect(tester.takeException(), isNull);
    await settle(tester, 3000);
  });

  testWidgets('🛍️ the Shop tab shows the shop', (tester) async {
    final fake = Fake([]);
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('tab_shop')));
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('shop_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('earn_card')), findsOneWidget);
    expect(find.textContaining('How to earn money'), findsOneWidget);
    expect(find.textContaining('try this next'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('👩 on Mum\'s list, the haggle says Mum pays', (tester) async {
    final fake = Fake([])
      ..wallet = 12.5
      ..first = {...game('Morning my dear! \$18 only.'), 'wallet': 12.5, 'mum_pays': true};
    await openHaggle(tester, [], fake: fake);
    expect(find.textContaining('Mum pays'), findsOneWidget);
    expect(find.textContaining('👛 \$12.50'), findsNothing);
    expect(tester.takeException(), isNull);
    await settle(tester, 3000);
  });

  testWidgets('a brand-new player is sent to Auntie Mei\'s mangoes for a first win', (tester) async {
    final fake = Fake([])..haggles = 0;
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.byKey(const ValueKey('first_haggle')), findsOneWidget);
    expect(find.textContaining("Auntie Mei's mangoes"), findsOneWidget);
    expect(find.byKey(const ValueKey('guess_card')), findsNothing);
  });

  testWidgets('the guided first deal keeps the important actions and rewards in view', (tester) async {
    MumGuide.enabled = true;
    final fake = Fake([
      {
        ...game('Deal lah!', event: 'accept', result: 'deal', deal: 13, stars: 2, saved: .28),
        'notes': ['Bonus reward'],
        'new_stickers': ['first_deal'],
      },
    ])..haggles = 0;
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('first_haggle')));
    await settle(tester, 1600);
    expect(find.byKey(const ValueKey('guess_card')), findsNothing);
    expect(find.text('Play together'), findsNothing);
    expect(find.text('Offer \$11'), findsOneWidget);
    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 600);
    await tester.tap(find.text('Confirm \$18'));
    await settle(tester, 2500);
    expect(find.text('Continue to market'), findsOneWidget);
    expect(find.text('Bonus reward'), findsNothing);
    await tester.tap(find.text('Deal details'));
    await settle(tester, 600);
    expect(find.text('Bonus reward'), findsOneWidget);
  });

  testWidgets('retrying an unsuccessful first haggle keeps the guided lesson', (tester) async {
    MumGuide.enabled = true;
    final fake = Fake([game('Never mind lah.', event: 'letgo', result: 'walked')])..haggles = 0;
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('first_haggle')));
    await settle(tester, 1600);
    await tester.tap(find.byKey(const ValueKey('walk')));
    await settle(tester, 2500);
    expect(find.text('You walked away 🚶'), findsOneWidget);
    fake.haggles = 1;
    await tester.tap(find.text('Try again'));
    await settle(tester, 1600);
    expect(find.byKey(const ValueKey('mum_tip')), findsOneWidget);
    expect(find.byKey(const ValueKey('guess_card')), findsNothing);
    expect(find.text('Offer \$11'), findsOneWidget);
  });

  testWidgets('a nickname is optional on the first launch and can be changed later', (tester) async {
    final fake = Fake([])
      ..named = false
      ..haggles = 0;
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.byKey(const ValueKey('first_haggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('name_save')), findsNothing);
    await tester.tap(find.text('Choose a nickname'));
    await settle(tester, 500);
    expect(find.byKey(const ValueKey('name_save')), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('name_save')), findsNothing);
    expect(fake.name, 'Caspar b');
    await tester.tap(find.byKey(const ValueKey('browse_market')));
    await settle(tester);
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

  testWidgets('buying two: the tag says each, and "Just one" goes back to one', (tester) async {
    final fake = await openHaggle(tester, [
      {...game('Two ah? OK, \$14 each.', event: 'bulk', ask: 14, qty: 2), 'one_text': 'Actually, just one lah.'},
      game('Just one ah? OK lah, one is \$18.', event: 'back_to_one'),
    ]);
    expect(find.byKey(const ValueKey('just_one')), findsNothing);
    await tester.tap(find.text('Wah, looks so good!'));
    await settle(tester);
    expect(find.text('each · 2 for \$28'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('just_one')));
    await settle(tester);
    expect(fake.sent.last['move'], 'one', reason: '${fake.sent}');
    expect(find.text('Actually, just one lah.'), findsOneWidget);
    expect(find.byKey(const ValueKey('just_one')), findsNothing);
    expect(find.textContaining('each ·'), findsNothing);
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

  testWidgets('🎤 talking: what you say goes into the box to check, then you send it', (tester) async {
    final voice = _Voice(['\$10', '\$10 can or not auntie']);
    Voice.instance = voice;
    final fake = await openHaggle(tester, [game('Aiyo \$10 cannot lah, \$16.', event: 'counter', ask: 16)]);
    await tester.tap(find.byKey(const ValueKey('mic')));
    await settle(tester, 600);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('reply_field')));
    expect(field.controller!.text, '\$10 can or not auntie');
    expect(fake.sent, isEmpty); // you check it first
    await tester.tap(find.text('Send'));
    await settle(tester, 2500);
    expect(fake.sent.last['text'], '\$10 can or not auntie');
    expect(voice.stopped, isTrue); // closing the box always turns the microphone off
    await settle(tester, 3000);
  });

  testWidgets("🎤 with \"Use my keyboard's mic\": the keyboard opens with a tip, the game doesn't listen", (
    tester,
  ) async {
    final voice = _Voice(['should not be heard']);
    Voice.instance = voice;
    Voice.useKeyboard = true;
    final fake = await openHaggle(tester, [game('Aiyo \$10 cannot lah, \$16.', event: 'counter', ask: 16)]);
    await tester.tap(find.byKey(const ValueKey('mic')));
    await settle(tester, 600);
    expect(find.textContaining('Tap the mic on your keyboard'), findsOneWidget);
    expect(Music.wanted, isNull); // quiet, so the keyboard's mic doesn't hear the tune
    final field = tester.widget<TextField>(find.byKey(const ValueKey('reply_field')));
    expect(field.controller!.text, isEmpty); // nothing heard by the game itself
    expect(field.focusNode!.hasFocus, isTrue); // the keyboard is up
    await tester.enterText(find.byKey(const ValueKey('reply_field')), '\$10 can or not auntie'); // what Gboard typed
    await tester.tap(find.text('Send'));
    await settle(tester, 2500);
    expect(fake.sent.last['text'], '\$10 can or not auntie');
    expect(Music.wanted, 'calm'); // the box closed: the music comes back
    await settle(tester, 3000);
  });

  testWidgets("🎤 on a phone that can't listen: says so, and you can still type", (tester) async {
    Voice.instance = _Voice(const [], works: false);
    final fake = await openHaggle(tester, [game('OK lah \$17.', event: 'counter', ask: 17)]);
    await tester.tap(find.byKey(const ValueKey('mic')));
    await settle(tester, 600);
    expect(find.textContaining("Voice typing isn't available"), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('reply_field')), 'cheaper can?');
    await tester.tap(find.text('Send'));
    await settle(tester, 2500);
    expect(fake.sent.last['text'], 'cheaper can?');
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
    await tester.tap(find.byKey(const ValueKey('tab_me')));
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
    // with a link that opens the same haggle for a friend, with this price to beat
    expect(parseChallenge(shared.single), (stall: 'mei', item: 'mango', price: 12.0, name: fake.name));
    await settle(tester, 3000);
  });

  testWidgets('past haggles: the list, and a chat to reread', (tester) async {
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await settle(tester);
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
    await tester.tap(find.byKey(const ValueKey('tab_stall')));
    await settle(tester);
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

  testWidgets('Music: the market tune, its own switch in Settings', (tester) async {
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    expect(Music.wanted, 'stroll');
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.drag(find.byKey(const ValueKey('music_volume')), const Offset(-2000, 0)); // all the way down
    await settle(tester, 400);
    expect(Music.level, 0);
    expect(Music.volumeOf('stroll'), 0);
    await tester.drag(find.byKey(const ValueKey('music_volume')), const Offset(2000, 0)); // all the way up
    await settle(tester, 400);
    expect(Music.level, 1);
    expect(Music.volumeOf('stroll'), closeTo(0.64, 1e-9));
    await tester.tap(find.byKey(const ValueKey('music_switch')));
    await settle(tester, 400);
    expect(Music.on, isFalse);
    expect(Music.wanted, isNull);
    expect(find.byKey(const ValueKey('music_volume')), findsNothing); // no slider while it's off
    await tester.tap(find.byKey(const ValueKey('music_switch')));
    await settle(tester, 400);
    expect(Music.wanted, 'stroll');
  });

  testWidgets("👩 Mum's tips in the first haggle: the first offer, her counter, No more tips, and her last word", (
    tester,
  ) async {
    MumGuide.enabled = true;
    final fake = await openHaggle(tester, [
      game('Aiyo, \$16 lah.', event: 'counter', ask: 16),
      game('OK lah OK lah, \$16!', event: 'accept', result: 'deal', deal: 16, stars: 1),
    ]);
    expect(find.byKey(const ValueKey('mum_tip')), findsOneWidget);
    expect(find.textContaining('Stallholders always start high'), findsOneWidget);
    await tester.tap(find.text('\$11 can or not?'));
    await settle(tester);
    expect(find.textContaining('She came down!'), findsOneWidget);
    expect(find.textContaining('Stallholders always start high'), findsNothing); // one tip at a time
    await tester.tap(find.byKey(const ValueKey('mum_skip')));
    await settle(tester, 300);
    expect(find.byKey(const ValueKey('mum_tip')), findsNothing);
    await tester.tap(find.text('OK lah, \$16'));
    await settle(tester, 600);
    await tester.tap(find.text('Confirm \$16'));
    await settle(tester, 2500);
    expect(find.textContaining('Mum: Well done!'), findsOneWidget); // she still says well done
    await settle(tester, 3000);
    // play again: no tips, and no last word from Mum
    fake.replies.add(game('OK lah OK lah, \$17!', event: 'accept', result: 'deal', deal: 17, stars: 1));
    await tester.ensureVisible(find.text('Again!'));
    await tester.tap(find.text('Again!'));
    await settle(tester);
    expect(find.byKey(const ValueKey('mum_tip')), findsNothing);
    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 600);
    await tester.tap(find.text('Confirm \$18'));
    await settle(tester, 2500);
    expect(find.textContaining('Mum: Well done!'), findsNothing);
    await settle(tester, 3000);
  });

  testWidgets("a friend's challenge link opens their haggle, with their price to beat and no surprise", (tester) async {
    startAddress = () => challengeLink(stall: 'mei', item: 'mango', price: 12.5, name: 'Melody');
    addTearDown(() => startAddress = () => '');
    final fake = Fake([]);
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2500);
    expect(find.textContaining("Beat Melody's \$12.50"), findsOneWidget);
    expect(fake.lastSurprise, '');
    expect(fake.lastAnyStall, isTrue);
  });

  testWidgets('a challenge link can be pasted under Friends', (tester) async {
    final fake = Fake([]);
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('tab_friends')));
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('challenge_paste')));
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('challenge_field')), 'nothing here');
    await tester.tap(find.byKey(const ValueKey('challenge_go')));
    await settle(tester, 600);
    expect(find.textContaining("doesn't look like a challenge link"), findsOneWidget);
    await settle(tester, 4000);
    await tester.tap(find.byKey(const ValueKey('challenge_paste')));
    await settle(tester, 600);
    final link = challengeLink(stall: 'mei', item: 'mango', price: 9, name: 'Ah Boy');
    await tester.enterText(find.byKey(const ValueKey('challenge_field')), 'Can you beat me? $link');
    await tester.tap(find.byKey(const ValueKey('challenge_go')));
    await settle(tester, 1500);
    expect(find.textContaining("Beat Ah Boy's \$9"), findsOneWidget);
    expect(fake.lastAnyStall, isTrue);
  });

  testWidgets('🔔 the daily reminder: on (a test notification, a week planned), the time shows, off clears it', (
    tester,
  ) async {
    final r = Reminder.instance as _Reminder;
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('reminder_switch')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await settle(tester, 300);
    // said no to notifications: stays off, and says how to allow them
    r.allowed = false;
    await tester.tap(find.byKey(const ValueKey('reminder_switch')));
    await settle(tester, 600);
    expect(find.textContaining('Notifications are off'), findsOneWidget);
    expect(r.shown, isEmpty);
    await settle(tester, 4000);
    r.allowed = true;
    await tester.tap(find.byKey(const ValueKey('reminder_switch')));
    await settle(tester, 800);
    expect(r.shown, ['🔔 Reminder on!']);
    expect(r.planned, isNotEmpty);
    expect(r.planned!.every((x) => x.at.hour == 19), isTrue);
    expect(find.text('19:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reminder_switch')));
    await settle(tester, 800);
    expect(r.planned, isEmpty); // off: nothing planned
  });

  testWidgets("🎤 \"Use my keyboard's mic\" can be switched on in Settings", (tester) async {
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('keyboard_mic')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('keyboard_mic')));
    await settle(tester, 400);
    expect(Voice.useKeyboard, isTrue);
  });

  testWidgets('✨ a legendary item: the banner on the market opens it (any stall), and its shares have no link', (
    tester,
  ) async {
    final shared = <String>[];
    shareBrag = (text, png) async => shared.add(text);
    capturePng = (_) async => null;
    final fake = Fake([
      game('Wah, you know good stuff. OK lah, \$60!', event: 'accept', result: 'deal', deal: 60, stars: 1)
        ..addAll({'legendary': true}),
    ])..legend = {'id': 'legend_mei', 'name': 'golden Musang King durian', 'emoji': '🍈', 'ask': 68, 'legendary': true};
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.text('✨ Legendary today only!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('legend_banner')));
    await settle(tester);
    expect(fake.lastAnyStall, isTrue);
    expect(fake.lastSurprise, '');
    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 600);
    await tester.tap(find.text('Confirm \$18'));
    await settle(tester, 2500);
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await settle(tester, 1000);
    expect(shared.single, contains('legendary'));
    expect(shared.single, isNot(contains('http'))); // gone tomorrow: no challenge link
    await settle(tester, 3000);
  });

  testWidgets('✨ on other days: when and where the next legendary is, never what', (tester) async {
    for (final (days, weekday, day, want) in [
      (1, 6, '2026-12-05', 'Tomorrow, at Madam Lee\'s'),
      (3, 6, '2026-12-05', 'Saturday, at Madam Lee\'s'),
      (12, 2, '2026-12-15', 'Tue 15 Dec, at Madam Lee\'s'),
    ]) {
      final fake = Fake([])
        ..nextLegend = {'days': days, 'weekday': weekday, 'day': day, 'stall': 'lee', 'stall_name': 'Madam Lee'};
      await tester.pumpWidget(const SizedBox()); // a fresh market each time
      await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
      await settle(tester, 2000);
      expect(find.byKey(const ValueKey('legend_teaser')), findsOneWidget);
      expect(find.textContaining(want), findsOneWidget);
      expect(find.textContaining('What could it be?'), findsOneWidget);
    }
  });

  testWidgets('✨ a legendary item already bought today says so and does not open', (tester) async {
    final fake = Fake([])
      ..legend = {
        'id': 'legend_mei',
        'name': 'golden Musang King durian',
        'emoji': '🍈',
        'ask': 68,
        'legendary': true,
        'sold_out': true,
      };
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.text("✨ You got today's legendary find!"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('legend_banner')));
    await settle(tester, 600);
    expect(find.textContaining('You already got today'), findsOneWidget);
    expect(fake.lastAnyStall, isFalse);
    await settle(tester, 4000);
  });

  testWidgets('🤜🤛 a tag-team combo: the COMBO! stamp and a line under her reply', (tester) async {
    await openHaggle(tester, [
      game('Wah, you two ah! OK lah, \$15.', event: 'counter', ask: 15)..addAll({'combo': true, 'combos': 1}),
    ]);
    await tester.tap(find.text('\$11 can or not?'));
    await settle(tester, 500);
    expect(find.byKey(const ValueKey('combo_stamp')), findsOneWidget);
    expect(find.textContaining('COMBO! One of you charmed her'), findsOneWidget);
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('combo_stamp')), findsNothing); // just a moment
  });

  testWidgets('💡 the result card has a tip for next time', (tester) async {
    await openHaggle(tester, [
      game('OK lah OK lah, \$18!', event: 'accept', result: 'deal', deal: 18, stars: 0)
        ..addAll({'coach': 'You paid her first price! Offer about 70% first.'}),
    ]);
    await tester.tap(find.text('OK lah, \$18'));
    await settle(tester, 600);
    await tester.tap(find.text('Confirm \$18'));
    await settle(tester, 2500);
    expect(find.text('💡 Next time: You paid her first price! Offer about 70% first.'), findsOneWidget);
    await settle(tester, 3000);
  });

  testWidgets('📖 the haggling guide: from Me, hidden tricks with hints, and real-life manners', (tester) async {
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('guide_open')));
    await settle(tester, 1000);
    expect(find.text('📖 Haggling guide'), findsOneWidget);
    expect(find.textContaining('0 of 12 tricks learned'), findsOneWidget);
    expect(find.text('???'), findsWidgets);
    expect(find.textContaining('Hint: Be nice before you talk price.'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('real_life')),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    expect(find.textContaining('chicken rice'), findsOneWidget);
  });

  testWidgets('Reduce motion can be switched on in Settings', (tester) async {
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(Fake([]))));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    expect(Motion.reduced, isFalse);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('reduce_motion')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('reduce_motion')));
    await settle(tester, 400);
    expect(Motion.reduced, isTrue);
    await tester.tap(find.byKey(const ValueKey('reduce_motion')));
    await settle(tester, 400);
    expect(Motion.reduced, isFalse);
  });

  testWidgets('a twist, a dilemma, saving a line, and the savings jar', (tester) async {
    final fake =
        Fake([
            game('Aiyo! \$17 lah.', event: 'counter', ask: 17)..addAll({
              'twist': {
                'text': "🐈 A cat darts off with one of Auntie Mei's mangoes!",
                'options': ['Chase the cat', 'Laugh'],
              },
            }),
          ])
          ..first = (game('Morning my dear! \$18 only.')
            ..addAll({
              'dilemma': {
                'text': "Auntie Mei's grandson needs new school shoes. Leave a little extra?",
                'cost': 3,
                'can': true,
              },
            }));
    fake.progress.addToJar(12);
    await tester.binding.setSurfaceSize(const Size(420, 1400)); // room for the chat and its cards
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('tab_stall')));
    await settle(tester);
    expect(find.textContaining('jar \$12'), findsOneWidget); // on the My stall tab (the shop strip)
    await tester.tap(find.byKey(const ValueKey('tab_market')));
    await settle(tester);
    await tester.ensureVisible(find.text('box of mangoes'));
    await tester.tap(find.text('box of mangoes'));
    await settle(tester);
    expect(find.byKey(const ValueKey('dilemma_card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dilemma_yes')));
    await settle(tester, 600);
    expect(fake.answered, ['dilemma true']);
    expect(find.byKey(const ValueKey('dilemma_card')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save_line')));
    await settle(tester, 600);
    expect(fake.saved, ['Morning my dear! \$18 only.']);
    expect(find.text('⭐ Saved'), findsOneWidget);
    await settle(tester, 4000);
    await tester.tap(find.text('\$11 can or not?'));
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('twist_card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('twist_0')));
    await settle(tester, 800);
    expect(fake.answered.last, 'twist 0');
    expect(find.textContaining('Catch it!'), findsOneWidget);
    expect(find.byKey(const ValueKey('twist_card')), findsNothing);
    await settle(tester, 3000);
  });

  testWidgets('a festival week shows on the market', (tester) async {
    final fake = Fake([])..festival = {'id': 'cny2027', 'name': 'Chinese New Year', 'emoji': '🧧', 'to': '2027-02-08'};
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.textContaining('🧧 Chinese New Year week at the market!'), findsOneWidget);
    await settle(tester, 2000);
  });

  testWidgets('home tabs: the market stays uncluttered; the rest is one tap away (a side rail on wide screens)', (
    tester,
  ) async {
    final fake = Fake([]);
    fake.progress.addToJar(40); // enough for the cake: a dot on the Shop tab
    tester.view.physicalSize = const Size(400, 900); // a phone
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(HawkerHaggleApp(api: apiFor(fake)));
    await settle(tester, 2000);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('shop_open')), findsNothing); // not on the market any more
    expect(find.byKey(const ValueKey('jar_open')), findsNothing);
    expect(find.text('box of mangoes'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Badge && w.isLabelVisible), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab_stall')));
    await settle(tester);
    expect(find.byKey(const ValueKey('shop_open')), findsOneWidget);
    expect(find.byKey(const ValueKey('jar_open')), findsOneWidget);
    expect(find.textContaining('You can afford something in the shop'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab_friends')));
    await settle(tester);
    expect(find.byKey(const ValueKey('friends_login')), findsOneWidget); // no account: how to get one
    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await settle(tester);
    for (final k in ['sticker_book', 'history', 'quotes_open', 'name_chip']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    // a wide screen (the web version on a computer): the same tabs down the side
    tester.view.physicalSize = const Size(1200, 900);
    await settle(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab_market')));
    await settle(tester);
    expect(find.text('box of mangoes'), findsOneWidget);
    await settle(tester, 2000);
  });

  testWidgets('what you can read in her face shows under her line, until the next move', (tester) async {
    await openHaggle(tester, [
      game('Aiyo, so sweet!', event: 'flattered', ask: 17)..['tells'] = ['😊 Auntie Mei is warming to you.'],
      game('Hmm, \$16.', event: 'counter', ask: 16),
    ]);
    await tester.tap(find.text('Wah, looks so good!'));
    await settle(tester, 1500);
    expect(find.text('😊 Auntie Mei is warming to you.'), findsOneWidget);
    await tester.tap(find.text('\$15 lah, OK?'));
    await settle(tester, 1500);
    expect(find.text('😊 Auntie Mei is warming to you.'), findsNothing);
    await settle(tester, 3000);
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
    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await settle(tester);
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
    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await settle(tester);
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

/// Pretend voice typing: "hears" [words] one after another, then stops.
class _Reminder implements Reminder {
  bool allowed = true;
  final shown = <String>[];
  List<Nudge>? planned;
  @override
  Future<bool> allow() async => allowed;
  @override
  Future<void> schedule(List<Nudge> plan) async => planned = plan;
  @override
  Future<void> showNow(String title, String body) async => shown.add(title);
}

class _Voice implements Voice {
  _Voice(this.words, {this.works = true});
  final List<String> words;
  final bool works;
  bool stopped = false;
  @override
  Future<bool> listen({
    required void Function(String words) onWords,
    required void Function(String? problem) onEnd,
    void Function(String language)? onReady,
  }) async {
    if (!works) return false;
    onReady?.call('English (Singapore)');
    for (final w in words) {
      onWords(w);
    }
    onEnd(null);
    return true;
  }

  @override
  Future<void> stop() async => stopped = true;
}
