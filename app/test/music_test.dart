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

  test('the volume: the middle is the normal level, the ends are silent and twice as loud', () async {
    expect(Music.volumeOf('stroll'), closeTo(0.48, 1e-9));
    expect(Music.volumeOf('calm'), closeTo(0.4, 1e-9));
    await Music.setLevel(0);
    expect(Music.volumeOf('calm'), 0);
    await Music.setLevel(1.7); // never past the end
    expect(Music.level, 1);
    expect(Music.volumeOf('calm'), closeTo(0.8, 1e-9));
  });
}
