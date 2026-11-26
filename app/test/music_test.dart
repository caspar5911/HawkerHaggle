import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/music.dart';
import 'package:hawker_haggle/sfx.dart';

void main() {
  setUp(() {
    Sfx.available = false; // the rules only: no audio plugin in tests
    Music.reset();
  });

  test('the market tune, the haggle tune on top, back again when the screen closes', () {
    expect(Music.wanted, 'stroll');
    final haggle = Music.enter('calm');
    expect(Music.wanted, 'calm');
    final inner = Music.enter('stroll');
    expect(Music.wanted, 'stroll');
    Music.leave(haggle); // screens may close out of order
    expect(Music.wanted, 'stroll');
    Music.leave(inner);
    expect(Music.wanted, 'stroll');
    Music.leave(inner); // twice is harmless
    expect(Music.wanted, 'stroll');
  });

  test('quiet while the microphone listens, and when switched off', () async {
    final haggle = Music.enter('calm');
    await Music.hush(true);
    expect(Music.wanted, isNull);
    await Music.hush(false);
    expect(Music.wanted, 'calm');
    await Music.setOn(false);
    expect(Music.wanted, isNull);
    Music.leave(haggle);
    expect(Music.wanted, isNull);
    await Music.setOn(true);
    expect(Music.wanted, 'stroll');
  });

  test('a player who had turned sound off before there was music starts with it off', () {
    expect(Music.startsOn(null, null), isTrue);
    expect(Music.startsOn(null, '0'), isTrue);
    expect(Music.startsOn(null, '1'), isFalse);
    expect(Music.startsOn('1', '1'), isTrue); // they switched music on themselves
    expect(Music.startsOn('0', '0'), isFalse);
  });
}
