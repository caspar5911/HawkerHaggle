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

import 'dart:math' as math;

import 'game_sweep_test.dart' show content;

import 'widget_test.dart' show Fake, settle;

/// A pretend market server with the same rules as server/hh/accounts.py (the server's own tests cover the real one).
class Market {
  final users = <String, Map<String, Object?>>{
    'admin': {'id': 1, 'username': 'admin', 'pw': 'admin', 'status': 'approved', 'admin': true, 'default': true},
  };
  final tokens = <String, String>{};
  final seen = <String>[];
  final saves = <String, Map<String, Object?>>{}; // username: {data, rev}
  Map<String, Object?> board = {'week': '2026-11-23', 'items': <Object>[], 'gossip': <Object>[]};
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
    // like the real server: UTF-8 JSON (progress can hold emoji and any language)
    http.Response out(int code, Object data) =>
        http.Response.bytes(utf8.encode(jsonEncode(data)), code, headers: {'content-type': 'application/json'});
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
      case '/ai/accounts/progress':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        return out(200, saves[tokens[tok]] ?? {'data': null, 'rev': 0});
      case '/ai/accounts/progress/save':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        final rev = (saves[tokens[tok]]?['rev'] ?? 0) as int;
        if (body['rev'] != rev) return out(409, {'detail': 'Newer progress was saved from another phone.'});
        saves[tokens[tok]!] = {'data': body['data'], 'rev': rev + 1};
        return out(200, {'rev': rev + 1});
      case '/ai/accounts/progress/delete':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        final had = saves[tokens[tok]];
        if (had == null) return out(200, {'rev': 0});
        saves[tokens[tok]!] = {'data': '', 'rev': (had['rev'] as int) + 1};
        return out(200, {'rev': (had['rev'] as int) + 1});
      case '/ai/accounts/board':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        return out(200, board);
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

/// A phone with the real game on it (its progress lives in [store], like secure storage on a real phone).
Api phone(Market m, [MemoryKeyValue? store]) {
  final kv = store ?? MemoryKeyValue();
  return Api(
    game: Game(content: content, store: kv, random: math.Random(4), unlockAll: true, surprises: false),
    content: content,
    store: kv,
    aiHttp: m.client,
    builtInEndpoint: 'https://glm.example/v1',
    builtInModel: 'gx10-current',
    syncDelay: const Duration(milliseconds: 1),
  );
}

/// Finish one haggle at Auntie Mei's (the first stall).
Future<void> haggleOnce(Api api) async {
  final s = (content['stalls'] as List).first as Map;
  final g = await api.start('${s['id']}', '${((s['items'] as List).first as Map)['id']}');
  await api.move('${g['id']}', move: 'buy');
}

Future<Map<String, dynamic>> me(Api api) => api.me();

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

  group('progress follows the account', () {
    test('a new account starts fresh if you say so; another phone sees it; logging out brings yours back', () async {
      final m = Market();
      final a = phone(m);
      await a.setName('Guest Me');
      await haggleOnce(a);
      expect((await me(a))['haggles'], 1);
      int? asked;
      await a.signIn(
        server: 'market.example.com',
        username: 'JingQi',
        password: 'kopi1234',
        signUp: true,
        bringProgress: (n) async {
          asked = n;
          return false;
        },
      );
      expect(asked, 1);
      expect((await me(a))['haggles'], 0); // the new account's own (empty) progress
      expect((await me(a))['named'], isFalse); // so the market asks for a name
      await a.setName('Jing Qi');
      await haggleOnce(a);
      await a.syncNow();
      expect(a.progressSaved, isTrue);
      expect('${m.saves['jingqi']!['data']}', contains('Jing Qi'));

      // another phone, same account: same progress, no question asked
      final b = phone(m);
      await b.setName('Someone Else');
      await b.signIn(
        server: 'market.example.com',
        username: 'jingqi',
        password: 'kopi1234',
        bringProgress: (_) async => fail('the account already has progress'),
      );
      expect((await me(b))['name'], 'Jing Qi');
      expect((await me(b))['haggles'], 1);

      // log out: this phone's own progress again
      await a.signOut();
      expect((await me(a))['name'], 'Guest Me');
      expect((await me(a))['haggles'], 1);
      await b.signOut();
      expect((await me(b))['name'], 'Someone Else');
    });

    test('or bring this phone\'s progress into the new account (the phone keeps its own copy)', () async {
      final m = Market();
      final a = phone(m);
      await a.setName('Ah Boy');
      await haggleOnce(a);
      await a.signIn(
        server: 'market.example.com',
        username: 'ahboy',
        password: 'kopi1234',
        signUp: true,
        bringProgress: (_) async => true,
      );
      expect((await me(a))['name'], 'Ah Boy');
      expect((await me(a))['haggles'], 1);
      await haggleOnce(a);
      await a.syncNow();
      expect(jsonDecode('${m.saves['ahboy']!['data']}')['haggles'], hasLength(2));
      await a.signOut();
      expect((await me(a))['haggles'], 1); // the guest progress didn't move
    });

    test('an empty phone just starts the account fresh without asking', () async {
      final m = Market();
      final a = phone(m);
      await a.signIn(
        server: 'market.example.com',
        username: 'newbie',
        password: 'kopi1234',
        signUp: true,
        bringProgress: (_) async => fail('nothing to bring'),
      );
      expect((await me(a))['haggles'], 0);
      expect(m.saves['newbie']!['rev'], 1);
    });

    test('the account\'s progress is still there after the app restarts, and picks up the newest copy', () async {
      final m = Market();
      final store = MemoryKeyValue();
      final a = phone(m, store);
      await a.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234', signUp: true);
      await a.setName('Jing Qi');
      await a.syncNow();
      // meanwhile another phone plays a haggle on the same account
      final b = phone(m);
      await b.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234');
      await haggleOnce(b);
      await b.syncNow();
      final again = phone(m, store); // the app opens again
      expect((await me(again))['name'], 'Jing Qi');
      expect((await me(again))['haggles'], 1);
    });

    test('two phones at once: the older one takes the newer progress instead of overwriting it', () async {
      final m = Market();
      final a = phone(m), b = phone(m);
      await a.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234', signUp: true);
      await b.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234');
      await b.setName('From B');
      await b.syncNow();
      await a.setName('From A'); // A hasn't seen B's save
      await a.syncNow();
      expect((await me(a))['name'], 'From B');
      expect('${m.saves['jingqi']!['data']}', contains('From B'));
    });

    test('delete my data while logged in clears the account copy too', () async {
      final m = Market();
      final a = phone(m);
      await a.setName('Guest Me');
      await haggleOnce(a);
      await a.signIn(
        server: 'market.example.com',
        username: 'jingqi',
        password: 'kopi1234',
        signUp: true,
        bringProgress: (_) async => true,
      );
      await a.syncNow();
      await a.deleteMe();
      await a.syncNow();
      expect((await me(a))['haggles'], 0);
      expect(jsonDecode('${m.saves['jingqi']!['data']}')['haggles'], isEmpty);
      await a.signOut();
      expect((await me(a))['haggles'], 0); // this phone's own copy went too
    });

    test('logged in on an older version: logged out once, so logging in again asks properly', () async {
      final m = Market();
      final store = MemoryKeyValue();
      final old = phone(m, store);
      await old.setName('Caspar');
      await haggleOnce(old);
      // what an older version left behind: logged in, but the progress never moved
      final t = m.login('arella');
      m.users['arella'] = {'id': 9, 'username': 'Arella', 'pw': 'x', 'status': 'pending'};
      await store.write(
        'account',
        jsonEncode(
          Account(server: 'https://market.example.com', username: 'Arella', token: t, status: 'pending').toJson(),
        ),
      );
      await store.write('ai_key', t);
      final now = phone(m, store);
      await now.ensureDevice();
      expect(now.account, isNull);
      expect(now.ai.apiKey, '');
      expect((await me(now))['name'], 'Caspar'); // nothing moved
      expect((await me(now))['haggles'], 1);
      expect(m.saves, isEmpty);
    });

    test(
      'admin progress follows the admin account too (from your own phone, the question; elsewhere, the same)',
      () async {
        final m = Market();
        // the owner tries a fresh browser first: nothing to bring, so the admin account starts empty
        final incognito = phone(m);
        await incognito.signIn(
          server: 'relay.example',
          username: 'admin',
          password: 'admin',
          bringProgress: (_) async => fail('nothing to bring'),
        );
        expect(incognito.ai.endpoint, 'https://glm.example/v1'); // the admin's AI doesn't change
        // then on their own phone, with real progress: the empty admin copy doesn't count, so it asks
        final mine = phone(m);
        await mine.setName('Caspar');
        await haggleOnce(mine);
        int? asked;
        await mine.signIn(
          server: 'relay.example',
          username: 'admin',
          password: 'admin',
          bringProgress: (n) async {
            asked = n;
            return true;
          },
        );
        expect(asked, 1);
        expect((await me(mine))['name'], 'Caspar');
        await mine.syncNow();
        // back in the fresh browser: log in again and it's Caspar's progress
        await incognito.signOut();
        await incognito.signIn(server: 'relay.example', username: 'admin', password: 'admin');
        expect((await me(incognito))['name'], 'Caspar');
        expect((await me(incognito))['haggles'], 1);
      },
    );
  });

  test('the board feeds the stallholders\' gossip', () async {
    final m = Market()
      ..board = {
        'week': '2026-11-23',
        'items': [
          {
            'stall': 'mei',
            'item': 'durian',
            'players': 1,
            'top': [
              {'name': 'Arella', 'price': 19, 'you': false},
            ],
            'you': null,
          },
        ],
        'gossip': [
          {'stall': 'mei', 'item': 'durian', 'name': 'Arella', 'day': '2026-11-25'},
        ],
      };
    final a = phone(m);
    expect(await a.board(), isNull); // not logged in
    await a.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234', signUp: true);
    final b = await a.board();
    expect((b!['items'] as List).single['top'][0]['name'], 'Arella');
    final r = await a.start('mei', 'mango', 'none');
    expect('${r['line']}', startsWith('Eh, your friend Arella came by also!'));
  });

  testWidgets('the market shows the board when logged in; Beat it starts that item with the target', (tester) async {
    final m = Market()
      ..board = {
        'week': '2026-11-23',
        'items': [
          {
            'stall': 'mei',
            'item': 'mango',
            'players': 1,
            'top': [
              {'name': 'Arella', 'price': 11, 'you': false},
            ],
            'you': null,
          },
        ],
        'gossip': <Object>[],
      };
    final api = apiWith(m, accountServer: 'https://market.example.com');
    await api.signIn(server: api.accountServer, username: 'jingqi', password: 'kopi1234', signUp: true);
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    expect(find.byKey(const ValueKey('board_open')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board_open')));
    await settle(tester, 1000);
    expect(find.text('🥇 Arella  \$11'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('beat_mei_mango')));
    await settle(tester, 1500);
    expect(find.text("🏆 Beat Arella's \$11!"), findsOneWidget);
    await settle(tester, 3000);
  });
}
