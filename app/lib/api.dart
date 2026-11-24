import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'core/ai_client.dart';
import 'core/game.dart';

/// Defaults for a private build (never put a private address in the public repo):
///   flutter build apk --dart-define=AI_ENDPOINT=https://host/v1 --dart-define=AI_MODEL=name
const defaultEndpoint = String.fromEnvironment('AI_ENDPOINT');
const defaultModel = String.fromEnvironment('AI_MODEL');

/// Which build this is, shown at the bottom of Settings: flutter build ... --dart-define=BUILD_LABEL="test 11".
const buildLabel = String.fromEnvironment('BUILD_LABEL', defaultValue: 'dev');

class ApiError implements Exception {
  ApiError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message;
}

/// Secure storage on the phone (Keystore-backed on Android, Keychain on iOS).
class SecureKeyValue implements KeyValue {
  SecureKeyValue([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// What the screens talk to. The whole game runs on the phone ([Game]); the only network use is the optional AI
/// endpoint set in Settings. With no AI set, the game plays in simple mode: taps, word rules, ready-made lines.
// Named parameters can't be private, so these fields are set in the initializer list.
// ignore_for_file: prefer_initializing_formals
class Api {
  Api({
    KeyValue? store,
    http.Client? aiHttp,
    Map? content,
    Game? game,
    this.builtInEndpoint = defaultEndpoint,
    this.builtInModel = defaultModel,
  }) : _store = store ?? SecureKeyValue(),
       _aiHttp = aiHttp,
       _content = content,
       _game = game;

  /// The AI this build came with (empty in the public build).
  final String builtInEndpoint;
  final String builtInModel;
  bool get hasBuiltInAi => builtInEndpoint.isNotEmpty;

  final KeyValue _store;
  final http.Client? _aiHttp;
  Map? _content;
  Game? _game;
  Future<void>? _ready;
  AiConfig _ai = const AiConfig();

  AiConfig get ai => _ai;

  Future<void> ensureDevice() => _ready ??= _init();

  Future<void> _init() async {
    _content ??= jsonDecode(await rootBundle.loadString('assets/content/stalls.json')) as Map;
    _ai = AiConfig(
      // A build that comes with an AI uses it unless another address was saved (an empty one doesn't count).
      endpoint: _orDefault(await _store.read('ai_endpoint'), builtInEndpoint),
      model: _orDefault(await _store.read('ai_model'), builtInModel),
      apiKey: await _store.read('ai_key') ?? '',
    );
    _game ??= Game(content: _content!, store: _store);
    _game!.ai = AiClient(_ai, client: _aiHttp);
    await _game!.load();
  }

  static String _orDefault(String? saved, String builtIn) => (saved == null || saved.trim().isEmpty) ? builtIn : saved;

  Future<T> _run<T>(FutureOr<T> Function(Game g) f) async {
    try {
      await ensureDevice();
      return await f(_game!);
    } on GameError catch (e) {
      throw ApiError(e.code, e.message);
    } catch (e) {
      if (e is ApiError) rethrow;
      throw ApiError(0, 'Something went wrong. Try again!');
    }
  }

  Future<Map<String, dynamic>> me() => _run((g) => Map<String, dynamic>.from(g.me()));
  Future<Map<String, dynamic>> stalls() => _run((g) => Map<String, dynamic>.from(g.stalls()));
  Future<Map<String, dynamic>> start(String stall, String item) =>
      _run((g) async => Map<String, dynamic>.from(await g.start(stall, item)));
  Future<Map<String, dynamic>> move(String id, {int? pick, String? move, String? text}) =>
      _run((g) async => Map<String, dynamic>.from(await g.move(id, pick: pick, move: move, text: text)));
  Future<void> flag(String id) => _run((g) => g.flag(id));
  Future<void> deleteMe() => _run((g) => g.deleteAll());
  Future<int> reportCount() => _run((g) => g.reports.length);
  Future<Map<String, dynamic>> today() => _run((g) => Map<String, dynamic>.from(g.today()));
  Future<List<Map<String, dynamic>>> stickers() =>
      _run((g) => [for (final s in g.stickers()) Map<String, dynamic>.from(s)]);
  Future<Map<String, dynamic>> stallProfile(String id) => _run((g) => Map<String, dynamic>.from(g.stallProfile(id)));
  Future<bool> hard() => _run((g) => g.hard);
  Future<void> setHard(bool on) => _run((g) => g.setHard(on));
  Future<String> reportsText() => _run((g) => g.reportsText());

  /// Settings > AI: point the game at any OpenAI-compatible endpoint (or none, for simple mode).
  Future<void> setAi({required String endpoint, required String model, required String apiKey}) async {
    await ensureDevice();
    _ai = AiConfig(endpoint: endpoint.trim(), model: model.trim(), apiKey: apiKey.trim());
    await _store.write('ai_endpoint', _ai.endpoint);
    await _store.write('ai_model', _ai.model);
    await _store.write('ai_key', _ai.apiKey);
    _game!.ai = AiClient(_ai, client: _aiHttp);
  }

  /// Settings > "Use default AI": back to the AI this build came with.
  Future<void> useBuiltInAi() => setAi(endpoint: builtInEndpoint, model: builtInModel, apiKey: '');

  Future<String> testAi({required String endpoint, required String model, required String apiKey}) async {
    final c = AiClient(
      AiConfig(endpoint: endpoint.trim(), model: model.trim(), apiKey: apiKey.trim()),
      client: _aiHttp,
    );
    if (!c.enabled) return 'No AI set: the game plays in simple mode.';
    return c.testConnection();
  }
}
