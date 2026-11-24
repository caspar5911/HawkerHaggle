import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// The game server's address, set at build time:
///   flutter build apk --dart-define=API_BASE=https://your-server
const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8090');

class ApiError implements Exception {
  ApiError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message;
}

/// Talks to the game server. The player is an anonymous device account: the server issues a random token on
/// first launch, kept in the phone's secure storage (Keychain on iOS, Keystore-backed on Android).
class Api {
  Api({http.Client? client, FlutterSecureStorage? storage, String? base})
    : _http = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage(),
      _base = base ?? apiBase;

  final http.Client _http;
  final FlutterSecureStorage _storage;
  String _base;
  bool _baseLoaded = false;
  String? _token;

  String get server => _base;

  /// Point the app at another server (test builds: Settings > Server). A new server means a new account there.
  Future<void> setServer(String url) async {
    final u = url.trim().replaceAll(RegExp(r'/+$'), '');
    _base = u.isEmpty ? apiBase : u;
    await _storage.write(key: 'server', value: _base);
    await _storage.delete(key: 'token');
    _token = null;
  }

  Future<void> ensureDevice() async {
    if (!_baseLoaded) {
      _baseLoaded = true;
      _base = (await _storage.read(key: 'server')) ?? _base;
    }
    _token ??= await _storage.read(key: 'token');
    if (_token == null) {
      final r = await _send('POST', '/v1/device', auth: false);
      _token = r['token'] as String;
      await _storage.write(key: 'token', value: _token);
    }
  }

  Future<Map<String, dynamic>> me() => _send('GET', '/v1/me');
  Future<Map<String, dynamic>> stalls() => _send('GET', '/v1/stalls');
  Future<Map<String, dynamic>> start(String stall, String item) =>
      _send('POST', '/v1/haggle', body: {'stall': stall, 'item': item});
  Future<Map<String, dynamic>> move(String id, {int? pick, String? move, String? text}) =>
      _send('POST', '/v1/haggle/$id/move', body: {'pick': ?pick, 'move': ?move, 'text': ?text});

  /// "She misunderstood me": reports the last typed message and her reply so the game can learn from it.
  Future<void> flag(String id) => _send('POST', '/v1/haggle/$id/flag');

  Future<void> deleteMe() async {
    await _send('DELETE', '/v1/me');
    await _storage.delete(key: 'token');
    _token = null;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool retried = false,
  }) async {
    if (auth) {
      await ensureDevice();
    } else if (!_baseLoaded) {
      _baseLoaded = true;
      _base = (await _storage.read(key: 'server')) ?? _base;
    }
    final uri = Uri.parse('$_base$path');
    final headers = {'Content-Type': 'application/json', if (auth && _token != null) 'Authorization': 'Bearer $_token'};
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      r = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 40)));
    } on TimeoutException {
      throw ApiError(0, 'The market is very busy. Try again!');
    } catch (_) {
      throw ApiError(0, "Can't reach the market. Check your internet.");
    }
    if (r.statusCode == 401 && auth && !retried) {
      // The server forgot this device (e.g. data deleted): register again once.
      await _storage.delete(key: 'token');
      _token = null;
      return _send(method, path, body: body, auth: auth, retried: true);
    }
    final data = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      final msg = data is Map && data['detail'] is String ? data['detail'] as String : 'Something went wrong.';
      throw ApiError(r.statusCode, msg);
    }
    return Map<String, dynamic>.from(data as Map);
  }
}
