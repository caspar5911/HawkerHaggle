// The 🎤's rules (the phone's recognizer itself can only be tried on a phone).
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/voice.dart';

void main() {
  final t0 = DateTime(2026, 11, 26, 10);
  DateTime at(int s) => t0.add(Duration(seconds: s));

  test('a pause in speech keeps listening, and the words of each stretch add up', () {
    final d = Dictation(t0);
    d.result(['auntie']);
    d.result(['auntie ten dollars']); // partial results replace each other within a stretch
    expect(d.again(at(3)), isTrue); // the phone stopped at a pause: listen again
    expect(d.words, 'auntie ten dollars');
    d.result(['can or not']);
    expect(d.words, 'auntie ten dollars can or not');
    expect(d.again(at(6)), isTrue);
    expect(d.again(at(9)), isFalse); // a stretch with nothing said: done
    expect(d.problem, isNull);
  });

  test('nothing heard at all says so; an error ends it; words heard are never lost to an error', () {
    final quiet = Dictation(t0);
    expect(quiet.again(at(5)), isFalse);
    expect(quiet.problem, 'nothing');
    expect(PhoneVoice.say(quiet.problem!), contains("Didn't hear anything"));
    final denied = Dictation(t0)..error('error_permission');
    expect(denied.again(at(1)), isFalse);
    expect(PhoneVoice.say(denied.problem!), contains('Allow the microphone'));
    final late = Dictation(t0)..result(['twelve dollars']);
    late.error('error_no_match');
    expect(late.again(at(4)), isFalse);
    expect(late.problem, isNull);
    expect(late.words, 'twelve dollars');
  });

  test('stopping (the ■, or the box closing) never listens again, and there is a time limit', () {
    final d = Dictation(t0)..result(['fifteen']);
    d.stopping = true;
    expect(d.again(at(2)), isFalse);
    expect(d.problem, isNull);
    final empty = Dictation(t0)..stopping = true;
    expect(empty.problem, isNull); // you stopped it yourself: no scolding
    final long = Dictation(t0, limit: const Duration(seconds: 40))..result(['and another thing']);
    expect(long.again(at(41)), isFalse);
    expect(Dictation(t0).left(at(39)), const Duration(seconds: 1));
  });
}
