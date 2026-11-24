// Accounts for playing without Tailscale: sign up, wait, get approved; the admin's 👑 Players screen; passwords.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:hawker_haggle/account_screens.dart' show statusText;
import 'package:hawker_haggle/accounts.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/main.dart';
import 'package:hawker_haggle/sfx.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'widget_test.dart' show Fake, settle;

/// A pretend market server with the same rules as server/hh/accounts.py (the server's own tests cover the real one).
class Market {
  final users = <String, Map<String, Object?>>{
    'admin': {'id': 1, 'username': 'admin', 'pw': 'admin', 'status': 'approved', 'admin': true, 'default': true},
  };
  final tokens = <String, String>{};
  final seen = <String>[];
  var n = 1;

  Map<String, Object?> pub(Map u) => {
    'username': u['username'],
    'status': u['status'],
    'admin': u['admin'] == true,
    'default_password': u['default'] == true,
  };

  String login(String user) {
    final t = 'hh_${tokens.length + 1}';
    tokens[t] = user;
    return t;
  }

  late final client = MockClient((req) async {
    seen.add(req.url.toString());
    final path = req.url.path;
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    final tok = (req.headers['Authorization'] ?? '').replaceFirst('Bearer ', '');
    final who = users[tokens[tok]];
    http.Response out(int code, Object data) => http.Response(jsonEncode(data), code);
    switch (path) {
      case '/ai/accounts/signup':
        final u = '${body['username']}'.toLowerCase();
        if (users.containsKey(u)) return out(409, {'detail': 'That username is taken. Try another one.'});
        users[u] = {'id': ++n, 'username': body['username'], 'pw': body['password'], 'status': 'pending'};
        return out(200, {'token': login(u), ...pub(users[u]!)});
      case '/ai/accounts/login':
        final u = users['${body['username']}'.toLowerCase()];
        if (u == null || u['pw'] != body['password']) return out(401, {'detail': 'Wrong username or password.'});
        return out(200, {'token': login('${u['username']}'.toLowerCase()), ...pub(u)});
      case '/ai/accounts/me':
        return who == null ? out(401, {'detail': 'Please log in again.'}) : out(200, pub(who));
      case '/ai/accounts/logout':
        tokens.remove(tok);
        return out(200, {'ok': true});
      case '/ai/accounts/password':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        if (who['pw'] != body['old']) return out(403, {'detail': 'Your current password is wrong.'});
        who['pw'] = body['new'];
        who['default'] = false;
        return out(200, {'ok': true});
      case '/ai/admin/players':
        if (who?['admin'] != true) return out(403, {'detail': 'Admin only'});
        return out(200, {
          'players': [
            for (final u in users.values.where((u) => u['admin'] != true))
              {
                'id': u['id'],
                'username': u['username'],
                'status': u['status'],
                'created_at': '2026-11-25T01:00:00',
                'ai_today': 0,
              },
          ],
          'ai_today': 0,
          'default_password': who!['default'] == true,
        });
      case '/ai/admin/decide':
        if (who?['admin'] != true) return out(403, {'detail': 'Admin only'});
        final u = users.values.firstWhere((u) => u['id'] == body['id']);
        if (body['action'] == 'reset') {
          u['pw'] = 'ab12-cd34-ef56';
          return out(200, {'password': 'ab12-cd34-ef56'});
        }
        u['status'] = {'approve': 'approved', 'reject': 'rejected', 'remove': 'removed'}[body['action']];
        return out(200, {'status': u['status']});
    }
    return out(404, {'detail': 'Not Found'});
  });
}

Api apiWith(Market m, {String accountServer = ''}) => Api(
  game: Fake([]),
  content: const {},
  store: MemoryKeyValue(),
  aiHttp: m.client,
  builtInEndpoint: 'https://glm.example/v1',
  builtInModel: 'gx10-current',
  accountServer: accountServer,
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    Sfx.available = false;
  });

  test('server addresses are tidied: no scheme, trailing slash or relay path needed', () {
    expect(serverAddress('market.example.com'), 'https://market.example.com');
    expect(serverAddress(' https://market.example.com/ '), 'https://market.example.com');
    expect(serverAddress('https://market.example.com/ai/v1'), 'https://market.example.com');
    expect(serverAddress('http://10.0.0.2:8090/ai/'), 'http://10.0.0.2:8090');
    expect(relayFor('market.example.com'), 'https://market.example.com/ai/v1');
  });

  test('a player signs up, waits, is approved; their login becomes the AI key; logging out goes back', () async {
    final m = Market();
    final api = apiWith(m);
    await api.ensureDevice();
    expect(api.ai.endpoint, 'https://glm.example/v1');
    final acc = await api.signIn(server: 'market.example.com', username: 'JingQi', password: 'kopi1234', signUp: true);
    expect(acc.status, 'pending');
    expect(api.ai.endpoint, 'https://market.example.com/ai/v1');
    expect(api.ai.apiKey, acc.token);
    expect(api.ai.model, 'gx10-current');
    m.users['jingqi']!['status'] = 'approved';
    expect((await api.refreshAccount())!.status, 'approved');
    await expectLater(
      api.signIn(server: 'market.example.com', username: 'jingqi', password: 'x', signUp: true),
      throwsA(isA<AccountError>().having((e) => e.message, 'message', contains('taken'))),
    );
    await api.signOut();
    expect(api.account, isNull);
    expect(api.ai.endpoint, 'https://glm.example/v1');
    expect(api.ai.apiKey, '');
  });

  test('logged out on the server (e.g. removed): logged out here too', () async {
    final m = Market();
    final api = apiWith(m);
    await api.signIn(server: 'market.example.com', username: 'ahboy', password: 'secret12', signUp: true);
    m.tokens.clear();
    await expectLater(api.refreshAccount(), throwsA(isA<AccountError>()));
    expect(api.account, isNull);
    expect(api.ai.endpoint, 'https://glm.example/v1');
  });

  test('the admin logs in without touching the AI settings, and can change the default password', () async {
    final m = Market();
    final api = apiWith(m, accountServer: 'https://relay.example');
    await api.ensureDevice();
    final acc = await api.signIn(server: api.accountServer, username: 'admin', password: 'admin');
    expect(acc.admin, isTrue);
    expect(acc.defaultPassword, isTrue);
    expect(api.ai.endpoint, 'https://glm.example/v1'); // still the GLM over Tailscale
    await expectLater(api.changePassword('wrong', 'new-pass-1'), throwsA(isA<AccountError>()));
    await api.changePassword('admin', 'new-pass-1');
    expect(api.account!.defaultPassword, isFalse);
    expect(m.users['admin']!['pw'], 'new-pass-1');
  });

  testWidgets('Settings: sign up, see "waiting", then approved after Check again', (tester) async {
    final m = Market();
    final api = apiWith(m, accountServer: 'https://market.example.com');
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('account_open')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('account_open')));
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('account_open')));
    await settle(tester, 600);
    expect(find.text('https://market.example.com'), findsOneWidget); // the build's market, ready
    await tester.enterText(find.byKey(const ValueKey('acc_user')), 'Jing Qi!'); // only allowed characters stay
    await tester.enterText(find.byKey(const ValueKey('acc_pw')), 'kopi1234');
    await tester.tap(find.byKey(const ValueKey('acc_signup')));
    await settle(tester, 1200);
    expect(m.users.containsKey('jingqi'), isTrue);
    expect(find.text('Logged in as JingQi'), findsOneWidget);
    expect(find.text(statusText('pending')), findsWidgets);
    expect(api.ai.endpoint, 'https://market.example.com/ai/v1'); // the game's AI now goes to the market
    m.users['jingqi']!['status'] = 'approved';
    await tester.ensureVisible(find.text('Check again'));
    await tester.tap(find.text('Check again'));
    await settle(tester, 800);
    expect(find.text(statusText('approved')), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('wrong password shows the reason in the dialog', (tester) async {
    final m = Market();
    final api = apiWith(m, accountServer: 'https://market.example.com');
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('account_open')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('account_open')));
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('account_open')));
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('acc_user')), 'admin');
    await tester.enterText(find.byKey(const ValueKey('acc_pw')), 'nope');
    await tester.tap(find.byKey(const ValueKey('acc_login')));
    await settle(tester, 800);
    expect(find.text('Wrong username or password.'), findsOneWidget);
    expect(api.account, isNull);
    await settle(tester, 4000);
  });

  testWidgets('admin: 👑 Players shows sign-ups; approve, reset a password; default-password warning goes away', (
    tester,
  ) async {
    final m = Market();
    m.users['ahboy'] = {'id': 7, 'username': 'ahboy', 'pw': 'x', 'status': 'pending'};
    final api = apiWith(m, accountServer: 'https://relay.example');
    await api.signIn(server: api.accountServer, username: 'admin', password: 'admin');
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('players_open')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('players_open')));
    await settle(tester, 300);
    expect(find.text('Logged in as admin 👑'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('players_open')));
    await settle(tester, 1000);
    expect(find.byKey(const ValueKey('default_pw_warning')), findsOneWidget);
    expect(find.text('1 waiting · 1 in all · 0 AI chats today'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('approve_ahboy')));
    await settle(tester, 1000);
    expect(m.users['ahboy']!['status'], 'approved');
    expect(find.byKey(const ValueKey('remove_ahboy')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('more_ahboy')));
    await settle(tester, 600);
    await tester.tap(find.text('Give a new password'));
    await settle(tester, 1000);
    expect(find.text('ab12-cd34-ef56'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await settle(tester, 600);
    // change the default password from the warning
    await tester.tap(find.text('Change password'));
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('pw_old')), 'admin');
    await tester.enterText(find.byKey(const ValueKey('pw_new')), 'teh-tarik-88');
    await tester.enterText(find.byKey(const ValueKey('pw_again')), 'teh-tarik-8');
    await tester.tap(find.byKey(const ValueKey('pw_save')));
    await settle(tester, 600);
    expect(find.text("The new passwords don't match."), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pw_again')), 'teh-tarik-88');
    await tester.tap(find.byKey(const ValueKey('pw_save')));
    await settle(tester, 1200);
    expect(m.users['admin']!['pw'], 'teh-tarik-88');
    expect(find.byKey(const ValueKey('default_pw_warning')), findsNothing);
    await settle(tester, 4000);
  });
}
