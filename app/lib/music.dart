import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sfx.dart';

/// Background music: two original looping tunes (see tools/make_music.py). "stroll" around the market, "calm" (softer)
/// under a haggle. It goes quiet while the 🎤 listens (or the phone would type the tune) and while the game is in the
/// background, and has its own switch in Settings. Like [Sfx], music never breaks the game: audio errors are ignored.
class Music {
  Music._();

  static const volumes = {'stroll': 0.3, 'calm': 0.25};

  /// The player's volume, 0 to 1. The middle is the normal level; all the way up is twice as loud.
  static double level = 0.5;

  /// How loud a tune plays at the player's [level].
  static double volumeOf(String tune) => (volumes[tune] ?? 0.3) * level * 2;

  /// The player's switch (on unless they turned it off).
  static bool on = true;
  static final _moods = <(Object, String)>[];
  static bool _hushed = false; // the microphone is listening
  static bool _away = false; // the game is in the background
  static bool _blocked = false; // the web version: browsers only allow sound after the first tap

  static AudioPlayer? _player;
  static String? _loaded; // the tune in the player
  static bool _playing = false;
  static double _volume = 0;
  static Future<void> _queue = Future.value();
  static const _storage = FlutterSecureStorage();

  /// The tune that should be playing now, or null for silence.
  static String? get wanted {
    if (!on || _hushed || _away || _blocked) return null;
    return _moods.isEmpty ? 'stroll' : _moods.last.$2;
  }

  static Future<void> init() async {
    if (!Sfx.available) return;
    _blocked = kIsWeb; // browsers refuse sound before the first tap (often without saying so), so wait for it
    try {
      on = startsOn(await _storage.read(key: 'music'), await _storage.read(key: 'muted'));
      level = (double.tryParse(await _storage.read(key: 'music_level') ?? '') ?? 0.5).clamp(0.0, 1.0);
    } catch (_) {}
    AppLifecycleListener(
      onStateChange: (s) {
        _away = s == AppLifecycleState.hidden || s == AppLifecycleState.paused || s == AppLifecycleState.detached;
        _update();
      },
    );
    _update();
  }

  /// On, unless switched off; a player who turned sound off before there was music starts without it too.
  @visibleForTesting
  static bool startsOn(String? music, String? muted) => music == null ? muted != '1' : music != '0';

  /// Changes the volume at once (while the slider moves); [save] when the finger lifts.
  static Future<void> setLevel(double value, {bool save = false}) async {
    level = value.clamp(0.0, 1.0);
    final p = _player, tune = _loaded;
    if (Sfx.available && p != null && tune != null && _playing) {
      try {
        await p.setVolume(_volume = volumeOf(tune));
      } catch (_) {}
    }
    if (save) {
      try {
        await _storage.write(key: 'music_level', value: level.toStringAsFixed(2));
      } catch (_) {}
    }
  }

  static Future<void> setOn(bool value) async {
    on = value;
    _blocked = false;
    _update();
    try {
      await _storage.write(key: 'music', value: value ? '1' : '0');
    } catch (_) {}
  }

  /// A screen with its own tune (e.g. 'calm' for a haggle). Returns a key for [leave] when the screen closes.
  static Object enter(String tune) {
    final key = Object();
    _moods.add((key, tune));
    _update();
    return key;
  }

  static void leave(Object key) {
    _moods.removeWhere((m) => m.$1 == key);
    _update();
  }

  /// Quiet while the microphone listens; the future completes once the music has stopped.
  static Future<void> hush(bool quiet) {
    _hushed = quiet;
    return _update().timeout(const Duration(milliseconds: 600), onTimeout: () {});
  }

  /// Any tap: in the web version, the first one lets the music start.
  static void tapped() {
    if (_blocked) {
      _blocked = false;
      _update();
    }
  }

  static Future<void> _update() {
    if (!Sfx.available) return Future.value();
    return _queue = _queue.then((_) => _apply()).catchError((_) {});
  }

  static Future<void> _apply() async {
    final tune = wanted;
    if (tune == null) {
      if (_playing) {
        if (!_hushed) await _fade(0); // the microphone can't wait for a fade
        await _player?.pause();
        _playing = false;
      }
      return;
    }
    if (_playing && _loaded == tune) return;
    final p = _player ??= await _make();
    if (_playing) {
      await _fade(0);
      await p.pause();
      _playing = false;
    }
    try {
      if (_loaded != tune) {
        await p.setSource(AssetSource('music/$tune.mp3'));
        _loaded = tune;
      }
      await p.setVolume(_volume = 0);
      await p.resume();
      _playing = true;
    } catch (_) {
      _blocked = true; // most likely the browser refusing sound before a tap
      return;
    }
    await _fade(volumeOf(tune));
  }

  static Future<AudioPlayer> _make() async {
    final p = AudioPlayer(playerId: 'music');
    try {
      await p.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    } catch (_) {}
    await p.setReleaseMode(ReleaseMode.loop);
    return p;
  }

  static Future<void> _fade(double to) async {
    final p = _player;
    if (p == null) return;
    final from = _volume;
    for (var i = 1; i <= 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await p.setVolume(_volume = from + (to - from) * i / 8);
    }
  }

  /// For tests: back to the start.
  @visibleForTesting
  static void reset() {
    on = true;
    level = 0.5;
    _moods.clear();
    _hushed = _away = _blocked = false;
  }
}
