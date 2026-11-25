import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'accounts.dart';
import 'core/ai_client.dart';
import 'core/game.dart';

/// Defaults for a private build (never put a private address in the public repo):
///   flutter build apk --dart-define=AI_ENDPOINT=https://host/v1 --dart-define=AI_MODEL=name
const defaultEndpoint = String.fromEnvironment('AI_ENDPOINT');
const defaultModel = String.fromEnvironment('AI_MODEL');

/// The market server whose accounts the Account screen offers first (a private build: the owner's relay; later a
/// public address). Players can type any other address.
const defaultAccountServer = String.fromEnvironment('ACCOUNT_SERVER');

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
    this.accountServer = defaultAccountServer,
    this.syncDelay = const Duration(seconds: 2),
  }) : _store = store ?? SecureKeyValue(),
       _aiHttp = aiHttp,
       _content = content,
       _game = game;

  /// The AI this build came with (empty in the public build).
  final String builtInEndpoint;
  final String builtInModel;
  bool get hasBuiltInAi => builtInEndpoint.isNotEmpty;
  final String accountServer;

  /// How long after a change the account's progress is sent to its server (a haggle saves many times).
  final Duration syncDelay;

  final KeyValue _store;
  final http.Client? _aiHttp;
  Map? _content;
  Game? _game;
  Future<void>? _ready;
  AiConfig _ai = const AiConfig();

  AiConfig get ai => _ai;
  Account? _account;
  Account? get account => _account;

  Future<void> ensureDevice() => _ready ??= _init();

  Future<void> _init() async {
    _content ??= jsonDecode(await rootBundle.loadString('assets/content/stalls.json')) as Map;
    _ai = AiConfig(
      // A build that comes with an AI uses it unless another address was saved (an empty one doesn't count).
      endpoint: _orDefault(await _store.read('ai_endpoint'), builtInEndpoint),
      model: _orDefault(await _store.read('ai_model'), builtInModel),
      apiKey: await _store.read('ai_key') ?? '',
    );
    _account = Account.fromJson(await _store.read('account'));
    _game ??= Game(content: _content!, store: _store);
    _game!.ai = AiClient(_ai, client: _aiHttp);
    _game!.onSaved = _changed;
    var a = _account;
    if (a != null && await _store.read(_keyFor(a)) == null) {
      // logged in on a version from before progress followed the account: log in again, which asks whether to
      // bring this phone's progress or start the account fresh
      final old = a;
      a = null;
      await _saveAccount(null);
      if (_ai.apiKey == old.token) await _applyAi(endpoint: builtInEndpoint, model: builtInModel, apiKey: '');
      unawaited(_accounts(old.server).logOut(old.token).catchError((_) {}));
    }
    if (_syncs(a)) {
      await _loadSync(a!);
      _game!.profileKey = _keyFor(a);
    }
    await _quietly(() => _game!.load());
    if (_syncs(a)) await _sync().timeout(const Duration(seconds: 6), onTimeout: () {});
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

  /// A stall's name from the content (for "a new stall opened").
  String stallName(String id) =>
      ((_content?['stalls'] as List?)?.cast<Map>().where((s) => s['id'] == id).firstOrNull?['name'] ?? id) as String;

  Future<Map<String, dynamic>> me() => _run((g) => Map<String, dynamic>.from(g.me()));
  Future<Map<String, dynamic>> stalls() => _run((g) => Map<String, dynamic>.from(g.stalls()));
  Future<Map<String, dynamic>> start(String stall, String item, [String? surprise]) =>
      _run((g) async => Map<String, dynamic>.from(await g.start(stall, item, surprise)));
  Future<Map<String, dynamic>> move(String id, {int? pick, String? move, String? text}) =>
      _run((g) async => Map<String, dynamic>.from(await g.move(id, pick: pick, move: move, text: text)));
  Future<void> flag(String id) => _run((g) => g.flag(id));
  Future<void> guess(String id, num price) => _run((g) => g.guess(id, price));
  Future<Map<String, dynamic>> shopStart([String? product]) =>
      _run((g) async => Map<String, dynamic>.from(await g.shopStart(product)));
  Future<Map<String, dynamic>> shopMove(String id, {double? ask, bool take = false, bool chat = false}) =>
      _run((g) async => Map<String, dynamic>.from(await g.shopMove(id, ask: ask, take: take, chat: chat)));

  /// Delete my data: this phone's progress, and the account's copy too when logged in.
  Future<void> deleteMe() => _run((g) async {
    final a = _account;
    if (_syncs(a)) {
      try {
        _rev = await _accounts(a!.server).deleteProgress(a.token);
      } on AccountError {
        throw ApiError(0, "Couldn't reach the market server, so nothing was deleted. Try again with internet.");
      }
      await _store.delete('profile');
    }
    await g.deleteAll(); // saves a fresh start, which goes to the account too
  });
  Future<int> reportCount() => _run((g) => g.reports.length);
  Future<Map<String, dynamic>> today() => _run((g) => Map<String, dynamic>.from(g.today()));
  Future<List<Map<String, dynamic>>> stickers() =>
      _run((g) => [for (final s in g.stickers()) Map<String, dynamic>.from(s)]);
  Future<Map<String, dynamic>> stallProfile(String id) => _run((g) => Map<String, dynamic>.from(g.stallProfile(id)));
  Future<bool> hard() => _run((g) => g.hard);
  Future<Map<String, dynamic>> challenges() => _run((g) => Map<String, dynamic>.from(g.challenges()));
  Future<List<Map<String, dynamic>>> history() =>
      _run((g) => [for (final h in g.history()) Map<String, dynamic>.from(h)]);
  Future<Map<String, dynamic>> historyItem(String id) => _run((g) => Map<String, dynamic>.from(g.historyItem(id)));
  Future<void> setHard(bool on) => _run((g) => g.setHard(on));
  Future<String> setName(String name) => _run((g) => g.setName(name));
  Future<String> randomName() => _run((g) => g.randomName());
  Future<String> reportsText() => _run((g) => g.reportsText());

  /// Settings > AI: point the game at any OpenAI-compatible endpoint (or none, for simple mode).
  Future<void> setAi({required String endpoint, required String model, required String apiKey}) async {
    await ensureDevice();
    await _applyAi(endpoint: endpoint, model: model, apiKey: apiKey);
  }

  Future<void> _applyAi({required String endpoint, required String model, required String apiKey}) async {
    _ai = AiConfig(endpoint: endpoint.trim(), model: model.trim(), apiKey: apiKey.trim());
    await _store.write('ai_endpoint', _ai.endpoint);
    await _store.write('ai_model', _ai.model);
    await _store.write('ai_key', _ai.apiKey);
    _game!.ai = AiClient(_ai, client: _aiHttp);
  }

  /// Settings > "Use default AI": back to the AI this build came with.
  Future<void> useBuiltInAi() => setAi(endpoint: builtInEndpoint, model: builtInModel, apiKey: '');

  // ---------------------------------------------------------------- accounts (playing without Tailscale)
  AccountClient _accounts(String server) => AccountClient(server, client: _aiHttp);

  /// Sign up or log in: the game shows that account's progress (kept on the server, so any phone that logs in sees
  /// the same). An account with no haggles yet starts fresh, or takes this phone's progress if [bringProgress] says
  /// so (asked only when this phone has some). A player's login also becomes their AI key for that server's relay;
  /// the admin's doesn't touch the AI settings (the owner plays over Tailscale).
  Future<Account> signIn({
    required String server,
    required String username,
    required String password,
    bool signUp = false,
    Future<bool> Function(int haggles)? bringProgress,
  }) async {
    await ensureDevice();
    if (_account != null) await signOut();
    final c = _accounts(server);
    final info = signUp ? await c.signUp(username, password) : await c.logIn(username, password);
    final acc = Account(server: c.server, username: '', token: '', status: '').withInfo(info);
    Map<String, dynamic>? saved;
    try {
      saved = await c.progress(acc.token);
    } on AccountError {
      saved = null; // no copy reachable: start as if new, and send it when the server answers
    }
    final data = '${saved?['data'] ?? ''}';
    final key = _keyFor(acc);
    final here = _game!.haggleCount;
    if (_haggles(data) == 0 && here > 0 && bringProgress != null && await bringProgress(here)) {
      await _store.write(key, _game!.exportProfile());
      _dirty = true;
    } else if (data.isNotEmpty) {
      await _store.write(key, data);
      _dirty = false;
    } else {
      await _store.delete(key);
      _dirty = true;
    }
    _rev = ((saved?['rev'] ?? 0) as num).toInt();
    await _saveAccount(acc);
    await _writeSync(acc);
    await _quietly(() => _game!.useProfile(key));
    if (!acc.admin) {
      await _applyAi(
        endpoint: relayFor(acc.server),
        model: _ai.model.isEmpty ? (builtInModel.isEmpty ? 'gx10-current' : builtInModel) : _ai.model,
        apiKey: acc.token,
      );
    }
    await syncNow();
    return acc;
  }

  // ---------------------------------------------------------------- progress follows the account
  Timer? _syncTimer;
  Future<void>? _syncing;
  int _rev = 0; // the server copy this phone's copy is based on
  bool _dirty = false; // changes not sent yet
  int _edits = 0;
  bool _switching = false;

  /// Logged in and everything is on the server.
  bool get progressSaved => !_dirty;

  static bool _syncs(Account? a) => a != null;

  /// Finished haggles in a saved copy (0 for none, an empty one or one that can't be read).
  static int _haggles(String data) {
    try {
      return ((jsonDecode(data) as Map)['haggles'] as List).length;
    } catch (_) {
      return 0;
    }
  }

  static String _who(Account a) => '${a.server}|${a.username.toLowerCase()}';
  static String _keyFor(Account a) => 'profile@${_who(a)}';
  static String _syncKey(Account a) => 'sync@${_who(a)}';

  Future<void> _loadSync(Account a) async {
    Map m = const {};
    try {
      m = jsonDecode(await _store.read(_syncKey(a)) ?? '{}') as Map;
    } catch (_) {}
    _rev = (m['rev'] as num?)?.toInt() ?? 0;
    _dirty = m['dirty'] == true;
  }

  Future<void> _writeSync(Account a) => _store.write(_syncKey(a), jsonEncode({'rev': _rev, 'dirty': _dirty}));

  /// Loading or switching profiles saves too: that isn't a change by the player.
  Future<void> _quietly(Future<void> Function() f) async {
    _switching = true;
    try {
      await f();
    } finally {
      _switching = false;
    }
  }

  void _changed() {
    final a = _account;
    if (_switching || !_syncs(a)) return;
    _edits++;
    if (!_dirty) {
      _dirty = true;
      unawaited(_writeSync(a!));
    }
    _syncTimer?.cancel();
    _syncTimer = Timer(syncDelay, () => unawaited(syncNow()));
  }

  /// Send this phone's changes to the account (or take a newer copy from another phone). Never throws: offline, it
  /// tries again after the next change or the next start.
  Future<void> syncNow() async {
    await ensureDevice();
    while (_syncing != null) {
      await _syncing;
    }
    final run = _sync();
    _syncing = run;
    try {
      await run;
    } finally {
      _syncing = null;
    }
  }

  Future<void> _sync() async {
    final a = _account;
    if (!_syncs(a)) return;
    final c = _accounts(a!.server);
    try {
      if (_dirty) {
        final edits = _edits;
        try {
          _rev = await c.saveProgress(a.token, _game!.exportProfile(), _rev);
          _dirty = _edits != edits;
        } on AccountError catch (e) {
          if (e.code != 409) rethrow;
          await _takeServerCopy(a, await c.progress(a.token)); // another phone saved newer progress: it wins
        }
      } else {
        final p = await c.progress(a.token);
        if (((p['rev'] ?? 0) as num).toInt() != _rev) await _takeServerCopy(a, p);
      }
      if (_account == a) await _writeSync(a);
    } on AccountError catch (e) {
      if (e.code == 401 && _account == a) await _forget(a);
    } catch (_) {
      // try again later
    }
  }

  Future<void> _takeServerCopy(Account a, Map p) async {
    await _quietly(() => _game!.importProfile('${p['data'] ?? ''}'));
    _rev = ((p['rev'] ?? 0) as num).toInt();
    _dirty = false;
  }

  Future<void> _saveAccount(Account? a) async {
    _account = a;
    if (a == null) {
      await _store.delete('account');
    } else {
      await _store.write('account', jsonEncode(a.toJson()));
    }
  }

  /// Ask the server for the latest status (waiting / approved / ...). Logged out there: logged out here too.
  Future<Account?> refreshAccount() async {
    await ensureDevice();
    final a = _account;
    if (a == null) return null;
    try {
      await _saveAccount(a.withInfo(await _accounts(a.server).me(a.token)));
    } on AccountError catch (e) {
      if (e.code == 401) await _forget(a);
      rethrow;
    }
    return _account;
  }

  /// Logged out: back to this phone's own progress (the account's stays on its server).
  Future<void> _forget(Account a) async {
    _syncTimer?.cancel();
    await _saveAccount(null);
    if (_ai.apiKey == a.token) await _applyAi(endpoint: builtInEndpoint, model: builtInModel, apiKey: '');
    if (_syncs(a)) {
      await _store.delete(_keyFor(a));
      await _store.delete(_syncKey(a));
      _rev = 0;
      _dirty = false;
      await _quietly(() => _game!.useProfile('profile'));
    }
  }

  Future<void> signOut() async {
    await ensureDevice();
    final a = _account;
    if (a == null) return;
    if (_syncs(a) && _dirty) await syncNow(); // last changes first
    try {
      await _accounts(a.server).logOut(a.token);
    } on AccountError {
      // logged out here anyway
    }
    await _forget(a);
  }

  Future<void> changePassword(String old, String neu) async {
    final a = _account;
    if (a == null) throw AccountError('Log in first.');
    await _accounts(a.server).changePassword(a.token, old, neu);
    await _saveAccount(a.withInfo({'default_password': false, 'admin': a.admin}));
  }

  /// This week's best prices among the market's players, and who came by lately (the stallholders' gossip).
  /// Null when not logged in or the server can't be reached.
  Future<Map<String, dynamic>?> board() async {
    await ensureDevice();
    final a = _account;
    if (a == null) return null;
    try {
      final b = await _accounts(a.server).board(a.token);
      final by = <String, List<Map>>{};
      for (final g in (b['gossip'] as List? ?? const []).cast<Map>()) {
        (by['${g['stall']}'] ??= []).add(g);
      }
      _game!.gossip = by;
      return b;
    } on AccountError {
      return null;
    }
  }

  Future<Map<String, dynamic>> players() async {
    final a = _account;
    if (a == null || !a.admin) throw AccountError('Admin only.');
    return _accounts(a.server).players(a.token);
  }

  Future<Map<String, dynamic>> decide(int id, String action) async {
    final a = _account;
    if (a == null || !a.admin) throw AccountError('Admin only.');
    return _accounts(a.server).decide(a.token, id, action);
  }

  Future<String> testAi({required String endpoint, required String model, required String apiKey}) async {
    final c = AiClient(
      AiConfig(endpoint: endpoint.trim(), model: model.trim(), apiKey: apiKey.trim()),
      client: _aiHttp,
    );
    if (!c.enabled) return 'No AI set: the game plays in simple mode.';
    return c.testConnection();
  }
}
