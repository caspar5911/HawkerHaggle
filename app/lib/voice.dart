/// Talking instead of typing: the phone's own speech recognition (Android's, or Chrome's in the web version). The
/// words land in the typing box, so the player sees what was heard and can fix it before sending.
library;

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract class Voice {
  /// The phone's voice typing (tests swap in a pretend one).
  static Voice instance = PhoneVoice();

  /// Starts listening. [onWords] gets the words heard so far; [onEnd] is called once when listening stops, with a
  /// short note for the player if something went wrong. False if voice typing can't be used here (no microphone
  /// permission, or no speech recognition on this phone).
  Future<bool> listen({
    required void Function(String words) onWords,
    required void Function(String? problem) onEnd,
    List<String> hints = const [],
  });

  Future<void> stop();
}

class PhoneVoice implements Voice {
  final _stt = SpeechToText();
  bool _ready = false;
  String? _locale;
  void Function(String?)? _onEnd;

  void _end(String? problem) {
    final f = _onEnd;
    _onEnd = null;
    f?.call(problem);
  }

  static String _say(SpeechRecognitionError e) => switch (e.errorMsg) {
    'error_no_match' => "Didn't catch that. Try again?",
    'error_speech_timeout' => "Didn't hear anything. Tap 🎤 and speak.",
    'error_permission' ||
    'error_insufficient_permissions' ||
    'not-allowed' => 'Allow the microphone for Hawker Haggle to talk.',
    'error_network' || 'network' => 'Voice typing needs the internet on this phone.',
    _ => 'Voice typing had a hiccup. Try again, or type.',
  };

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onError: (e) => _end(_say(e)),
        onStatus: (s) {
          if (s == SpeechToText.doneStatus) _end(null);
        },
      );
      if (_ready) {
        // Singapore English if the phone has it (it knows "lah" and "can or not"), else US English
        final all = await _stt.locales();
        String? pick(String id) =>
            all.where((l) => l.localeId.replaceAll('-', '_').toLowerCase() == id).firstOrNull?.localeId;
        _locale = pick('en_sg') ?? pick('en_us');
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
    List<String> hints = const [],
  }) async {
    if (!await _init()) return false;
    _onEnd = onEnd;
    try {
      await _stt.listen(
        onResult: (r) => onWords(r.recognizedWords),
        listenOptions: SpeechListenOptions(
          localeId: _locale,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
          contextualPhrases: hints,
        ),
      );
    } catch (_) {
      _onEnd = null;
      return false;
    }
    return true;
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
