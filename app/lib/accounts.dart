// Accounts on the market's server, for players who come in through a public address instead of Tailscale.
// Sign up, wait for the admin to approve, then the login token is the AI key. The admin approves players here too.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AccountError implements Exception {
  AccountError(this.message, [this.code = 0]);
  final String message;
  final int code;
  @override
  String toString() => message;
}

/// "hisdomain.com", "https://hisdomain.com/", ".../ai/v1" all become "https://hisdomain.com".
String serverAddress(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (!s.contains('://')) s = 'https://$s';
  s = s.replaceAll(RegExp(r'/+$'), '');
  for (final tail in ['/ai/v1/chat/completions', '/v1/chat/completions', '/ai/v1', '/ai', '/v1']) {
    if (s.endsWith(tail)) {
      s = s.substring(0, s.length - tail.length);
      break;
    }
  }
  return s.replaceAll(RegExp(r'/+$'), '');
}

/// The AI address for a server: its relay.
String relayFor(String server) => '${serverAddress(server)}/ai/v1';

class Account {
  const Account({
    required this.server,
    required this.username,
    required this.token,
    required this.status,
    this.admin = false,
    this.defaultPassword = false,
  });
  final String server;
  final String username;
  final String token;
  final String status; // pending, approved, rejected, removed
  final bool admin;
  final bool defaultPassword;

  Account withInfo(Map info) => Account(
    server: server,
    username: '${info['username'] ?? username}',
    token: '${info['token'] ?? token}',
    status: '${info['status'] ?? status}',
    admin: info['admin'] == true,
    defaultPassword: info['default_password'] == true,
  );

  Map<String, Object?> toJson() => {
    'server': server,
    'username': username,
    'token': token,
    'status': status,
    'admin': admin,
    'default_password': defaultPassword,
  };

  static Account? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map;
      return Account(
        server: '${m['server']}',
        username: '${m['username']}',
        token: '${m['token']}',
        status: '${m['status']}',
        admin: m['admin'] == true,
        defaultPassword: m['default_password'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

class AccountClient {
  AccountClient(String server, {http.Client? client}) : server = serverAddress(server), _http = client ?? http.Client();
  final String server;
  final http.Client _http;

  Future<Map<String, dynamic>> _post(String path, {Map<String, Object?>? body, String? token}) async {
    if (server.isEmpty) throw AccountError('Type the market server address first.');
    final http.Response r;
    try {
      r = await _http
          .post(
            Uri.parse('$server/ai/$path'),
            headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
            body: jsonEncode(body ?? const {}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw AccountError("Couldn't reach the market server. Check the address and your internet.");
    }
    Map<String, dynamic> data = const {};
    try {
      data = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {}
    if (r.statusCode == 200) return data;
    final detail = data['detail'];
    if (r.statusCode == 404 || r.statusCode == 405) {
      throw AccountError("This address doesn't have player accounts.", r.statusCode);
    }
    throw AccountError(detail is String ? detail : 'Something went wrong (${r.statusCode}).', r.statusCode);
  }

  Future<Map<String, dynamic>> signUp(String username, String password) =>
      _post('accounts/signup', body: {'username': username.trim(), 'password': password});
  Future<Map<String, dynamic>> logIn(String username, String password) =>
      _post('accounts/login', body: {'username': username.trim(), 'password': password});
  Future<Map<String, dynamic>> me(String token) => _post('accounts/me', token: token);
  Future<void> logOut(String token) => _post('accounts/logout', token: token);
  Future<void> changePassword(String token, String old, String neu) =>
      _post('accounts/password', token: token, body: {'old': old, 'new': neu});

  // game progress, one copy per account: {data: text or null, rev}
  Future<Map<String, dynamic>> progress(String token) => _post('accounts/progress', token: token);
  Future<int> saveProgress(String token, String data, int rev) async =>
      ((await _post('accounts/progress/save', token: token, body: {'data': data, 'rev': rev}))['rev'] as num).toInt();
  Future<int> deleteProgress(String token) async =>
      ((await _post('accounts/progress/delete', token: token))['rev'] as num).toInt();

  // friends: this week's best prices, and who bought what lately
  Future<Map<String, dynamic>> board(String token) => _post('accounts/board', token: token);

  // live co-op rooms (the host's phone runs the haggle; the server only passes messages)
  Future<Map<String, dynamic>> coopCreate(String token, String stall, String item) =>
      _post('coop/create', token: token, body: {'stall': stall, 'item': item});
  Future<Map<String, dynamic>> coopJoin(String token, String code) =>
      _post('coop/join', token: token, body: {'code': code});
  Future<Map<String, dynamic>> coopSend(String token, String code, Map<String, Object?> msg) =>
      _post('coop/send', token: token, body: {'code': code, 'msg': msg});
  Future<Map<String, dynamic>> coopPull(String token, String code, int after) =>
      _post('coop/pull', token: token, body: {'code': code, 'after': after});
  Future<void> coopLeave(String token, String code) => _post('coop/leave', token: token, body: {'code': code});

  // admin
  Future<Map<String, dynamic>> players(String token) => _post('admin/players', token: token);

  // ✨ legendary events: everyone reads them (no login); the admin posts and removes them
  Future<Map<String, dynamic>> legendary() => _post('legendary');
  Future<Map<String, dynamic>> adminLegend(String token) => _post('admin/legend', token: token);
  Future<Map<String, dynamic>> legendCreate(String token, Map<String, Object?> event) =>
      _post('admin/legend/create', token: token, body: event);
  Future<void> legendDelete(String token, int id) => _post('admin/legend/delete', token: token, body: {'id': id});
  Future<Map<String, dynamic>> stats(String token) => _post('admin/stats', token: token);
  Future<Map<String, dynamic>> decide(String token, int id, String action) =>
      _post('admin/decide', token: token, body: {'id': id, 'action': action});
}
