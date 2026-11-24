import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Little sound effects. Short, original synth sounds (see tools/make_sounds.py), mixed with the player's own
/// music rather than pausing it. Sound never breaks the game: any audio error is ignored.
class Sfx {
  Sfx._();

  static const names = ['pop', 'chat', 'coin', 'deal', 'huff', 'hmm', 'whoosh', 'star', 'aww'];

  /// Turned off in widget tests (no audio plugin there).
  static bool available = true;
  static bool muted = false;
  static final _pools = <String, Future<AudioPool>>{};
  static const _storage = FlutterSecureStorage();

  static Future<void> init() async {
    if (!available) return;
    try {
      muted = (await _storage.read(key: 'muted')) == '1';
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      for (final n in names) {
        _pool(n).ignore();
      }
    } catch (_) {}
  }

  static Future<void> setMuted(bool m) async {
    muted = m;
    try {
      await _storage.write(key: 'muted', value: m ? '1' : '0');
    } catch (_) {}
  }

  static Future<AudioPool> _pool(String n) => _pools.putIfAbsent(
    n,
    () => AudioPool.createFromAsset(
      path: 'sfx/$n.wav',
      maxPlayers: 3,
      playerMode: kIsWeb ? PlayerMode.mediaPlayer : PlayerMode.lowLatency,
    ),
  );

  static void play(String name, {double volume = 0.8}) {
    if (!available || muted) return;
    unawaited(() async {
      try {
        // Low-latency players are not handed back automatically; every sound is under 1s, so return it after 1.5s.
        final stop = await (await _pool(name)).start(volume: volume);
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await stop();
      } catch (_) {}
    }());
  }

  /// The sound for a stallholder's reply.
  static void forEvent(String event) {
    switch (event) {
      case 'accept':
        play('coin');
      case 'confirm':
        play('star', volume: 0.6);
      case 'insulted' || 'rude':
        play('huff');
      case 'competitor_annoyed' || 'flattery_tired' || 'refuse' || 'final' || 'plead_no' || 'pity_tired':
        play('hmm');
      case 'letgo':
        play('whoosh');
      default:
        play('chat', volume: 0.6);
    }
  }
}
