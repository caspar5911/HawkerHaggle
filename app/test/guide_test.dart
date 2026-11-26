import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/challenge_link.dart';
import 'package:hawker_haggle/guide.dart';

Map g({String event = 'greet', num? pending, bool done = false, List sug = const [1, 2, 3]}) => {
  'event': event,
  'pending': pending,
  'done': done,
  'suggestions': sug,
};

void main() {
  setUp(() {
    MumGuide.enabled = true;
    MumGuide.again = false;
  });

  test("Mum's tips: the first haggle only, unless asked again; never in a haggle together", () {
    expect(MumGuide.wanted(haggles: 0), isTrue);
    expect(MumGuide.wanted(haggles: 1), isFalse);
    expect(MumGuide.wanted(haggles: 0, together: true), isFalse);
    MumGuide.again = true;
    expect(MumGuide.wanted(haggles: 9), isTrue);
    expect(MumGuide.wanted(haggles: 9), isFalse); // used up
    MumGuide.enabled = false;
    expect(MumGuide.wanted(haggles: 0), isFalse);
  });

  test('a tip at each moment that matters, each once', () {
    final seen = <String>{};
    (String, String)? tip(Map s, int moves, {bool canTap = true}) {
      final t = mumTip(s, moves: moves, seen: seen, canTap: canTap);
      if (t != null) seen.add(t.$1);
      return t;
    }

    expect(tip(g(), 0)!.$1, 'start');
    expect(tip(g(), 0), isNull); // once
    expect(tip(g(event: 'counter'), 1)!.$1, 'counter');
    expect(tip(g(event: 'counter'), 2)!.$1, 'talk');
    expect(tip(g(event: 'counter'), 3), isNull); // nothing more to say
    expect(tip(g(event: 'insulted'), 4)!.$1, 'cross');
    expect(tip(g(event: 'final'), 5)!.$1, 'final');
    expect(tip(g(event: 'accept', pending: 12), 6)!.$1, 'pending');
    expect(tip(g(event: 'accept', pending: 12, done: true), 7), isNull);
    expect(mumWellDone({'result': 'deal'}), contains('Well done'));
    expect(mumWellDone({'result': 'walked'}), contains('Never mind'));
  });

  test('in Hard mode (nothing to tap) the first tip says to type', () {
    final t = mumTip(g(sug: const []), moves: 0, seen: {}, canTap: false)!;
    expect(t.$2, contains('Type an offer'));
    expect(mumTip(g(), moves: 0, seen: {}, canTap: true)!.$2, contains('Tap a price'));
  });

  test('challenge links: made and read back, also inside a message', () {
    final link = challengeLink(stall: 'mei', item: 'mango', price: 12.5, name: 'Melody <3');
    expect(link, startsWith(webHome));
    expect(parseChallenge(link), (stall: 'mei', item: 'mango', price: 12.5, name: 'Melody 3'));
    final msg = 'I got the box of mangoes for \$12.50! Can you beat me? Try here: $link #HawkerHaggle';
    expect(parseChallenge(msg)?.price, 12.5);
    // no name: "A friend"
    expect(parseChallenge(challengeLink(stall: 'mei', item: 'mango', price: 3, name: '!!'))?.name, 'A friend');
  });

  test('broken or odd challenge links are ignored', () {
    expect(parseChallenge(''), isNull);
    expect(parseChallenge('no link here'), isNull);
    expect(parseChallenge('$webHome?stall=mei&item=mango'), isNull); // no price
    expect(parseChallenge('$webHome?beat=-3&stall=mei&item=mango'), isNull);
    expect(parseChallenge('$webHome?beat=abc&stall=mei&item=mango'), isNull);
    expect(parseChallenge('$webHome?beat=NaN&stall=mei&item=mango'), isNull);
    expect(parseChallenge('$webHome?beat=3&stall=../x&item=mango'), isNull);
    expect(parseChallenge('$webHome?beat=3&stall=mei'), isNull);
  });
}
