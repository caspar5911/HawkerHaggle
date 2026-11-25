/// Talking instead of typing: the phone's own speech recognition (Google's on Android, Chrome's in the web version).
/// The phone turns your voice into words; the game only ever sees the words, which land in the typing box so the
/// player can check and fix them before sending.
library;

import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract class Voice {
  /// The phone's voice typing (tests swap in a pretend one).
  static Voice instance = PhoneVoice();

  /// Starts listening. [onReady] says the phone is really listening now (words said before that are lost), with the
  /// language it listens in. [onWords] gets everything heard so far. [onEnd] is called once when listening stops,
  /// with a short note for the player if nothing was heard or something went wrong. False if voice typing can't be
  /// used here (no microphone permission, or no speech recognition on this phone).
  Future<bool> listen({
    required void Function(String words) onWords,
    required void Function(String? problem) onEnd,
    void Function(String language)? onReady,
  });

  /// Stops listening (the words so far stay). Safe to call any time; nothing restarts after it.
  Future<void> stop();
}

/// The rules of one 🎤 session, apart from the phone's recognizer so they can be tested.
///
/// The phone's recognizer stops by itself after a short pause in speech (Google's, about a second or two, and it
/// ignores requests for longer). So a session is made of stretches: a stretch in which you said something is kept and
/// listening starts again for the next one; it ends when you tap stop, after a stretch with nothing said, on an error,
/// or after [limit] in all.
class Dictation {
  Dictation(this.start, {this.limit = const Duration(seconds: 40)});
  final DateTime start;
  final Duration limit;

  String _kept = ''; // earlier stretches
  String _now = ''; // this stretch so far
  bool _heard = false; // anything said in this stretch
  String? _error; // the recognizer's error code
  bool stopping = false; // the player tapped stop, or the box closed: never listen again
  bool live = false; // the phone said it's listening

  /// Everything heard so far.
  String get words => [_kept, _now].where((w) => w.isNotEmpty).join(' ');

  /// How long the next stretch may last.
  Duration left(DateTime now) {
    final l = limit - now.difference(start);
    return l < const Duration(seconds: 1) ? const Duration(seconds: 1) : l;
  }

  /// Words for this stretch (the recognizer's guesses, best first).
  void result(List<String> guesses) {
    final w = guesses.isEmpty ? '' : guesses.first.trim();
    _now = w;
    if (w.isNotEmpty) _heard = true;
  }

  void error(String code) => _error ??= code;

  /// A stretch ended: true to listen again (the words so far are kept).
  bool again(DateTime now) {
    if (stopping || _error != null || !_heard || now.difference(start) >= limit) return false;
    _kept = words;
    _now = '';
    _heard = false;
    return true;
  }

  /// Why it ended, for the player: null if words were heard (or they stopped it themselves), else the error code
  /// ('nothing' if the phone heard nothing at all).
  String? get problem => words.isNotEmpty || (stopping && _error == null) ? null : (_error ?? 'nothing');
}

class PhoneVoice implements Voice {
  final _stt = SpeechToText();
  bool _ready = false;
  String? _locale;
  String _language = '';
  Dictation? _d;
  Timer? _restart, _watchdog;
  void Function(String)? _onWords;
  void Function(String?)? _onEnd;
  void Function(String)? _onReady;

  static String say(String code) => switch (code) {
    'nothing' || 'error_no_match' || 'error_speech_timeout' => "Didn't hear anything. Tap 🎤 and speak up.",
    'error_permission' ||
    'error_insufficient_permissions' ||
    'not-allowed' => 'Allow the microphone for Hawker Haggle to talk.',
    'error_network' || 'error_network_timeout' || 'network' => 'Voice typing needs the internet on this phone.',
    'no_start' => "The microphone didn't start. Tap 🎤 to try again.",
    _ => 'Voice typing had a hiccup. Try again, or type.',
  };

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(onError: _error, onStatus: _status);
      if (_ready) {
        // Singapore English if the phone has it, else US English (else the phone's own language)
        final all = await _stt.locales();
        LocaleName? pick(String id) =>
            all.where((l) => l.localeId.replaceAll('-', '_').toLowerCase() == id).firstOrNull;
        final l = pick('en_sg') ?? pick('en_us');
        _locale = l?.localeId;
        _language = l?.name ?? '';
      }
    } catch (_) {
      _ready = false; // not remembered: the player may allow the microphone next time
    }
    return _ready;
  }

  @override
  Future<bool> listen({
    required void Function(String words) onWords,
    required void Function(String? problem) onEnd,
    void Function(String language)? onReady,
  }) async {
    if (_d != null) _finish();
    if (!await _init()) return false;
    final d = _d = Dictation(DateTime.now());
    _onWords = onWords;
    _onEnd = onEnd;
    _onReady = onReady;
    return _stretch(d);
  }

  Future<bool> _stretch(Dictation d) async {
    if (_d != d || d.stopping) return false;
    // if the phone never says it's listening (it was still busy), end with a note instead of waiting forever
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 3), () {
      if (_d == d && !d.live) {
        d.error('no_start');
        _finish();
      }
    });
    try {
      await _stt.listen(
        onResult: (r) {
          if (_d != d) return;
          d.result([for (final a in r.alternates) a.recognizedWords]);
          _onWords?.call(d.words);
        },
        listenOptions: SpeechListenOptions(
          localeId: _locale,
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          listenFor: d.left(DateTime.now()),
        ),
      );
    } catch (_) {
      d.error('no_start');
      _finish();
      return false;
    }
    return true;
  }

  void _status(String s) {
    final d = _d;
    if (d == null) return;
    if (s == SpeechToText.listeningStatus) {
      d.live = true;
      _watchdog?.cancel();
      _onReady?.call(_language);
    } else if (s == SpeechToText.doneStatus) {
      d.live = false;
      if (d.again(DateTime.now())) {
        _restart?.cancel();
        _restart = Timer(const Duration(milliseconds: 250), () => _stretch(d));
      } else {
        _finish();
      }
    }
  }

  void _error(SpeechRecognitionError e) {
    final d = _d;
    if (d == null) return;
    d.error(e.errorMsg);
    _finish();
  }

  void _finish() {
    final d = _d;
    if (d == null) return;
    d.stopping = true;
    _d = null;
    _restart?.cancel();
    _watchdog?.cancel();
    if (_stt.isListening) _stt.stop().ignore();
    final f = _onEnd;
    _onEnd = _onWords = null;
    _onReady = null;
    final p = d.problem;
    f?.call(p == null ? null : say(p));
  }

  @override
  Future<void> stop() async {
    final d = _d;
    if (d == null) return;
    d.stopping = true; // no more stretches, whatever comes next
    _restart?.cancel();
    if (!d.live) return _finish();
    try {
      await _stt.stop(); // the last words arrive, then "done" ends it
    } catch (_) {}
    // in case "done" never comes
    Timer(const Duration(milliseconds: 1500), () {
      if (_d == d) _finish();
    });
  }
}
